import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../services/error_reporter.dart';

class ExtraInstructionsWidget extends StatefulWidget {
  final String? title;
  final String? titleTranslationKey;
  final List<Map<String, dynamic>>? initialInstructions;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final int maxInstructions;

  const ExtraInstructionsWidget({
    super.key,
    this.title,
    this.titleTranslationKey,
    this.initialInstructions,
    required this.onChanged,
    this.maxInstructions = 5,
  });

  @override
  State<ExtraInstructionsWidget> createState() =>
      _ExtraInstructionsWidgetState();
}

class _ExtraInstructionsWidgetState extends State<ExtraInstructionsWidget>
    with SingleTickerProviderStateMixin {
  late List<Map<String, dynamic>> _instructions;
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;

  // Recording state
  bool _isRecording = false;
  bool _isProcessing = false;
  DateTime? _recordStartTime;
  int? _reRecordIndex; // non-null when re-recording a specific instruction

  // Typing state
  bool _showTextInput = false;
  int? _editingIndex; // non-null when editing existing instruction inline
  final _textController = TextEditingController();
  final _textFocusNode = FocusNode();

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _instructions = widget.initialInstructions != null
        ? List<Map<String, dynamic>>.from(
            widget.initialInstructions!.map((e) => Map<String, dynamic>.from(e)))
        : [];

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initSpeech();
  }

  Future<void> _initSpeech() async {
    if (Platform.isAndroid) {
      _speechAvailable = await _speech.initialize(
        onError: (_) {
          if (mounted) {
            setState(() {
              _isRecording = false;
              _isProcessing = false;
            });
            _pulseController.stop();
            _pulseController.reset();
          }
        },
        onStatus: _handleSpeechStatus,
      );
    }
  }

  void _handleSpeechStatus(String status) {
    // Some Android STT engines transition straight to "done" / "notListening"
    // without delivering an onResult callback. Recover the UI in that case.
    if (status == 'done' || status == 'notListening') {
      if (mounted && _isProcessing) {
        setState(() {
          _isProcessing = false;
          _isRecording = false;
        });
        _pulseController.stop();
        _pulseController.reset();
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _textController.dispose();
    _textFocusNode.dispose();
    if (_speech.isListening) _speech.stop();
    super.dispose();
  }

  void _notifyChanged() {
    widget.onChanged(List<Map<String, dynamic>>.from(
        _instructions.map((e) => Map<String, dynamic>.from(e))));
  }

  bool _micDenied = false;

  // ==================== SPEECH METHODS ====================

  Future<void> _ensureMicPermission() async {
    final prefs = await SharedPreferences.getInstance();
    final rationaleShown = prefs.getBool('mic_rationale_shown') ?? false;
    if (rationaleShown) return;

    if (!mounted) return;
    final allowed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.mic, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text('mic_permission_title'.tr())),
          ],
        ),
        content: Text(
          'mic_permission_body'.tr(),
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('not_now'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: Text('allow'.tr()),
          ),
        ],
      ),
    );

    await prefs.setBool('mic_rationale_shown', true);

    if (allowed != true) {
      if (mounted) {
        setState(() => _micDenied = true);
        _showMicDeniedSnackbar();
      }
    }
  }

  void _onMicDown() async {
    if (!Platform.isAndroid) {
      _showToast('voice_android_only'.tr());
      return;
    }
    if (_micDenied) {
      _showMicDeniedSnackbar();
      return;
    }
    if (_instructions.length >= widget.maxInstructions && _reRecordIndex == null) {
      _showToast('max_instructions'.tr());
      return;
    }

    await _ensureMicPermission();
    if (_micDenied) return;

    if (!_speechAvailable) {
      // Try re-initializing — user may have granted system permission
      _speechAvailable = await _speech.initialize(
        onError: (_) {
          if (mounted) {
            setState(() {
              _isRecording = false;
              _isProcessing = false;
            });
            _pulseController.stop();
            _pulseController.reset();
          }
        },
        onStatus: _handleSpeechStatus,
      );
      if (!_speechAvailable) {
        if (mounted) {
          setState(() => _micDenied = true);
          _showMicDeniedSnackbar();
        }
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _isRecording = true;
      _recordStartTime = DateTime.now();
    });
    _pulseController.repeat(reverse: true);

    try {
      await _speech.listen(
        onResult: _onSpeechResult,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        localeId: _getLocaleId(),
      );
    } catch (e, st) {
      await ErrorReporter.reportError(e, st, hint: 'voice_recognition');
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _isProcessing = false;
      });
      _pulseController.stop();
      _pulseController.reset();
      SnackbarHelper.showError(context, 'voice_could_not_start'.tr());
      return;
    }
    // After awaiting listen, confirm the engine actually started.
    if (!_speech.isListening && mounted && _isRecording) {
      setState(() {
        _isRecording = false;
        _isProcessing = false;
      });
      _pulseController.stop();
      _pulseController.reset();
      SnackbarHelper.showError(context, 'voice_could_not_start'.tr());
    }
  }

  void _onMicUp() {
    if (!_isRecording) return;

    final held = DateTime.now().difference(_recordStartTime!);
    if (held.inMilliseconds < 1000) {
      _speech.stop();
      _pulseController.stop();
      _pulseController.reset();
      setState(() {
        _isRecording = false;
      });
      _showToast('hold_longer'.tr());
      return;
    }

    setState(() {
      _isRecording = false;
      _isProcessing = true;
    });
    _pulseController.stop();
    _pulseController.reset();
    _speech.stop();
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!result.finalResult) return;
    if (!mounted) return;

    setState(() {
      _isProcessing = false;
      _isRecording = false;
    });
    _pulseController.stop();
    _pulseController.reset();

    if (result.recognizedWords.isEmpty) {
      // Silence or noise — do NOT save an entry.
      SnackbarHelper.showInfo(context, 'voice_nothing_heard'.tr());
      return;
    }

    final text = result.recognizedWords;
    setState(() {
      if (_reRecordIndex != null) {
        _instructions[_reRecordIndex!]['text'] = text;
        _instructions[_reRecordIndex!]['language'] = _detectLanguage(text);
        _reRecordIndex = null;
      } else {
        _addInstruction(text);
      }
    });
    _notifyChanged();
    _showToast('instruction_added'.tr(), isSuccess: true);
  }

  String _getLocaleId() {
    final locale = context.locale;
    if (locale.languageCode == 'ur') return 'ur_PK';
    return 'en_US';
  }

  String _detectLanguage(String text) {
    final urduPattern = RegExp(r'[\u0600-\u06FF]');
    return urduPattern.hasMatch(text) ? 'ur' : 'en';
  }

  // ==================== INSTRUCTION MANAGEMENT ====================

  void _addInstruction(String text) {
    if (text.trim().isEmpty) return;
    if (_instructions.length >= widget.maxInstructions) return;

    _instructions.add({
      'order': _instructions.length + 1,
      'text': text.trim(),
      'language': _detectLanguage(text),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    _renumber();
  }

  void _deleteInstruction(int index) {
    setState(() {
      _instructions.removeAt(index);
      _renumber();
    });
    _notifyChanged();
  }

  void _renumber() {
    for (int i = 0; i < _instructions.length; i++) {
      _instructions[i]['order'] = i + 1;
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _instructions.removeAt(oldIndex);
      _instructions.insert(newIndex, item);
      _renumber();
    });
    _notifyChanged();
  }

  void _startReRecord(int index) {
    if (!Platform.isAndroid) {
      _showToast('voice_android_only'.tr());
      return;
    }
    if (!_speechAvailable) {
      _showToast('could_not_understand'.tr());
      return;
    }
    _reRecordIndex = index;
    _onMicDown();
  }

  void _startEditText(int index) {
    setState(() {
      _editingIndex = index;
      _textController.text = _instructions[index]['text'];
      _showTextInput = false;
    });
  }

  void _confirmEdit() {
    if (_editingIndex != null && _textController.text.trim().isNotEmpty) {
      setState(() {
        _instructions[_editingIndex!]['text'] = _textController.text.trim();
        _instructions[_editingIndex!]['language'] =
            _detectLanguage(_textController.text);
        _editingIndex = null;
        _textController.clear();
      });
      _notifyChanged();
    }
  }

  void _cancelEdit() {
    setState(() {
      _editingIndex = null;
      _textController.clear();
    });
  }

  void _submitTextInstruction() {
    if (_textController.text.trim().isEmpty) return;
    setState(() {
      _addInstruction(_textController.text);
      _textController.clear();
      _showTextInput = false;
    });
    _notifyChanged();
    _showToast('instruction_added'.tr(), isSuccess: true);
  }

  void _showToast(String message, {bool isSuccess = false}) {
    if (!mounted) return;
    if (isSuccess) {
      SnackbarHelper.showSuccess(context, message);
    } else {
      SnackbarHelper.showInfo(context, message);
    }
  }

  void _showMicDeniedSnackbar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('mic_denied_message'.tr()),
        action: SnackBarAction(
          label: 'open_settings_button'.tr(),
          onPressed: () => openAppSettings(),
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    final sectionTitle = widget.title ??
        (widget.titleTranslationKey != null
            ? widget.titleTranslationKey!.tr()
            : 'extra_instructions'.tr());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Icon(Icons.mic, color: AppColors.primary, size: 22),
            const SizedBox(width: 8),
            Text(
              sectionTitle,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Instructions card
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Instructions list or placeholder
              if (_instructions.isEmpty && !_showTextInput)
                _buildPlaceholder()
              else
                _buildInstructionsList(),

              // Text input field
              if (_showTextInput && _editingIndex == null) _buildTextInputRow(),

              // Recording/processing status
              if (_isRecording) _buildRecordingIndicator(),
              if (_isProcessing) _buildProcessingIndicator(),

              // Action buttons row
              _buildActionButtons(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Column(
        children: [
          Icon(Icons.record_voice_over_outlined,
              size: 40, color: AppColors.textHint),
          const SizedBox(height: 8),
          Text(
            'press_hold_mic'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionsList() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _instructions.length,
        onReorder: _onReorder,
        proxyDecorator: (child, index, animation) {
          return AnimatedBuilder(
            animation: animation,
            builder: (context, child) => Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: child,
            ),
            child: child,
          );
        },
        itemBuilder: (context, index) {
          return _buildInstructionRow(index);
        },
      ),
    );
  }

  Widget _buildInstructionRow(int index) {
    final instruction = _instructions[index];
    final isEditing = _editingIndex == index;

    return Container(
      key: ValueKey('instruction_$index'),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        border: index < _instructions.length - 1
            ? const Border(
                bottom: BorderSide(color: AppColors.divider, width: 1))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Drag handle
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.drag_handle, color: AppColors.textHint, size: 22),
            ),
          ),
          // Number badge
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '#${instruction['order']}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.info,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Text or edit field
          Expanded(
            child: isEditing
                ? Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          autofocus: true,
                          style: const TextStyle(fontSize: 14),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding:
                                EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _confirmEdit(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.check, color: AppColors.success, size: 20),
                        onPressed: _confirmEdit,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppColors.error, size: 20),
                        onPressed: _cancelEdit,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  )
                : Text(
                    instruction['text'],
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                      height: 1.3,
                    ),
                  ),
          ),
          // 3-dot menu
          if (!isEditing)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20, color: AppColors.textSecondary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onSelected: (action) => _handleMenuAction(action, index),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      const Icon(Icons.edit, size: 18),
                      const SizedBox(width: 8),
                      Text('edit'.tr()),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 're_record',
                  child: Row(
                    children: [
                      const Icon(Icons.mic, size: 18),
                      const SizedBox(width: 8),
                      Text('recording'.tr().replaceAll('...', '')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(Icons.delete, size: 18, color: AppColors.error),
                      const SizedBox(width: 8),
                      Text('delete'.tr(),
                          style: const TextStyle(color: AppColors.error)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _handleMenuAction(String action, int index) {
    switch (action) {
      case 'edit':
        _startEditText(index);
        break;
      case 're_record':
        _startReRecord(index);
        break;
      case 'delete':
        _showDeleteConfirmation(index);
        break;
    }
  }

  void _showDeleteConfirmation(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('delete_instruction'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('cancel'.tr()),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteInstruction(index);
            },
            child: Text('delete'.tr(),
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  Widget _buildTextInputRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              focusNode: _textFocusNode,
              autofocus: true,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'type_instruction'.tr(),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onSubmitted: (_) => _submitTextInstruction(),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.send, color: AppColors.primary),
            onPressed: _submitTextInstruction,
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
            onPressed: () => setState(() {
              _showTextInput = false;
              _textController.clear();
            }),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) => Transform.scale(
              scale: _pulseAnimation.value,
              child: const Icon(Icons.circle, color: AppColors.error, size: 12),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'recording'.tr(),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.error,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            'converting'.tr(),
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    final atMax = _instructions.length >= widget.maxInstructions;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (atMax)
            Expanded(
              child: Text(
                'max_instructions'.tr(),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          // Keyboard button
          if (!atMax && _editingIndex == null)
            _ActionCircleButton(
              icon: Icons.keyboard,
              color: AppColors.textSecondary,
              size: 44,
              onTap: () {
                setState(() {
                  _showTextInput = !_showTextInput;
                  if (_showTextInput) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _textFocusNode.requestFocus();
                    });
                  }
                });
              },
            ),
          const SizedBox(width: 10),
          // Mic button (press & hold)
          if (_editingIndex == null)
            GestureDetector(
              onLongPressStart: atMax && _reRecordIndex == null
                  ? null
                  : (_) => _onMicDown(),
              onLongPressEnd: (_) => _onMicUp(),
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  final scale = _isRecording ? _pulseAnimation.value : 1.0;
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isRecording
                            ? AppColors.error
                            : (atMax ? AppColors.textHint : AppColors.primary),
                        boxShadow: [
                          BoxShadow(
                            color: (_isRecording
                                    ? AppColors.error
                                    : AppColors.primary)
                                .withValues(alpha: 0.3),
                            blurRadius: _isRecording ? 16 : 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.mic, color: Colors.white, size: 28),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionCircleButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onTap;

  const _ActionCircleButton({
    required this.icon,
    required this.color,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size / 2),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}
