part of '../../screens/home_screen.dart';

extension _DashboardFeedbackMethods on _HomeScreenState {
      _showTransactionInfo(
        'There is no notification entry waiting for review.',
        title: 'Nothing to review',
      );
      return;
    }
    _smartInputCtrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    final saved =
        await _processNLP(text, source: SmartInputSource.notification);
    if (saved && Hive.isBoxOpen('preferences')) {
      await Hive.box('preferences').delete(
        NotificationEntryService.pendingReviewKey,
      );
    }

                        _showTransactionError(
                          'Choose a different name for this category.',
                          title: 'Category already exists',
                        );
                        return;
                      }
                      Navigator.pop(ctx);
                      Future.delayed(const Duration(milliseconds: 300), () {
                        if (_categoryScrollCtrl.hasClients) {
                          _categoryScrollCtrl.animateTo(_categoryScrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                        }
                      }

    _showDeletionMessage(
      "Category '$category' was deleted.",
      title: 'Category deleted',
    );
  }

  // ==================== TRANSACTION / TRANSFER MODAL ====================
  Future<bool?> _showAddOrEditModal({
    Expense? existing,
    String? prefilledAmount,
    String? prefilledTitle,
    String? prefilledCategory,
    DateTime? prefilledDate,
    String? preselectedWalletId,
    String initialType = 'expense',
    String? reviewMessage,
  }

                            _showTransferMessage(
                              'Money was moved between the selected wallets.',
                            );
                          } else if (transactionType == 'income') {
                            _showIncomeMessage(
                              'The income was added to the selected wallet.',
                            );
                          }

                            _showIncomeMessage(
                              'The income was added to the selected wallet.',
                            );
                          } else {
                            _showExpenseMessage(
                              'The expense was saved to the selected wallet.',
                            );
                          }

                            _showExpenseMessage(
                              'The expense was saved to the selected wallet.',
                            );
                          }
                        }
                        if (preferenceEntry != null) {
                          unawaited(
                            _rememberSmartEntryPreference(preferenceEntry),
                          );
                        }

    _showTopMessage(
      title: title,
      message: message,
      tone: TransactionMessageTone.error,
    );
  }

  void _showTransactionSuccess(
      String message, {
        String title = 'Completed',
        String? actionLabel,
        Future<void> Function()? onAction,
      }

  void _showTransactionSuccess(
      String message, {
        String title = 'Completed',
        String? actionLabel,
        Future<void> Function()? onAction,
      }
}
