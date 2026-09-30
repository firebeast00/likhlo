import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import "../services/notification_service.dart";
import '../services/notification_entry_service.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/category_provider.dart';
import '../providers/wallet_provider.dart';
import '../models/expense_model.dart';
import '../models/debt_model.dart';
import '../models/wallet_model.dart';
import '../app/app_shell.dart';
import '../app/app_navigation.dart';
import '../features/smart_entry/smart_entry_controller.dart';
import '../features/smart_entry/smart_entry_batch_controller.dart';
import '../features/smart_entry/transaction_batch_draft.dart';
import 'batch_transaction_review_screen.dart';
import '../features/voice/voice_entry_controller.dart';
import '../features/feedback/feedback_coordinator.dart';
import 'dashboard_screen.dart';
import '../widgets/primary_ledger_tabs.dart';
import '../widgets/dashboard_app_bar.dart';
import '../widgets/transaction_message_card.dart';
import '../services/local_nlp_service.dart';
import '../services/ocr_scanner_service.dart';
import '../services/speech_session_controller.dart';
import '../services/transaction_executor.dart';
import '../services/smart_command.dart';
import '../services/smart_input_engine.dart';
import '../services/confidence_evaluator.dart';
import '../services/speech_recognition_provider.dart';
import '../services/speech_command_completeness.dart';
import '../services/transaction_title_policy.dart';
import './income_accounts_screen.dart';
import './receipt_review_screen.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'interactive_ocr_screen.dart';

part '../features/dashboard/dashboard_coordinator.dart';
part '../features/dashboard/dashboard_notifications.dart';
part '../features/dashboard/dashboard_core_actions.dart';
part '../features/dashboard/dashboard_navigation.dart';
part '../features/dashboard/dashboard_categories.dart';
part '../features/dashboard/dashboard_transaction_form.dart';
part '../features/dashboard/dashboard_feedback_methods.dart';
part '../features/dashboard/dashboard_transaction_widgets.dart';
part '../features/dashboard/dashboard_category_widgets.dart';
part '../features/dashboard/dashboard_smart_input_widget.dart';
part '../features/dashboard/dashboard_wallet_actions.dart';
part '../features/dashboard/dashboard_hero_widgets.dart';
part '../features/dashboard/dashboard_month_selector.dart';
part '../features/dashboard/dashboard_voice.dart';
part '../features/dashboard/dashboard_ocr.dart';
part '../features/dashboard/dashboard_smart_entry_matching.dart';
part '../features/dashboard/dashboard_smart_entry_transfer.dart';
part '../features/dashboard/dashboard_smart_entry_queries.dart';
part '../features/dashboard/dashboard_smart_entry_mutation.dart';
part '../features/dashboard/dashboard_smart_entry_processing.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

