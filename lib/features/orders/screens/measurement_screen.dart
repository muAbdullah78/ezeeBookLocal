import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/page_transitions.dart';
import '../../../models/measurement.dart';
import '../widgets/extra_instructions_widget.dart';
import 'order_details_screen.dart';

class MeasurementScreen extends StatefulWidget {
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String customerGender;
  final int customerSerialNumber;
  final String stitchType;
  final List<Measurement>? savedMeasurements;

  const MeasurementScreen({
    super.key,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.customerGender,
    required this.customerSerialNumber,
    required this.stitchType,
    this.savedMeasurements,
  });

  @override
  State<MeasurementScreen> createState() => _MeasurementScreenState();
}

class _MeasurementScreenState extends State<MeasurementScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  // ==================== GENDER HELPERS ====================
  bool get _isMale => widget.customerGender == 'male';
  bool get _isFemale => widget.customerGender == 'female';

  bool get _showShirt =>
      widget.stitchType == 'full_suit' ||
      widget.stitchType == 'naap_suit' ||
      widget.stitchType == 'only_shirt';

  bool get _showBottom =>
      widget.stitchType == 'full_suit' ||
      widget.stitchType == 'naap_suit' ||
      widget.stitchType == 'only_shalwar_trouser';

  bool get _showDupatta =>
      widget.stitchType == 'full_suit' && _isFemale;

  bool get _isNaapSuit => widget.stitchType == 'naap_suit';

  // Naap suit expand state
  bool _shirtExpanded = false;
  bool _bottomExpanded = false;

  // ==================== MEN'S STATE ====================
  final Map<String, TextEditingController> _menShirtControllers = {};
  final Map<String, TextEditingController> _menBottomControllers = {};
  bool _collarNok = false;
  bool _collarBan = false;
  String _sidePocket = 'none';
  bool _frontPocket = false;
  bool _trouserPocket = false;
  bool _shalwarPocket = false;
  late TabController _menBottomTabController;
  String _menSelectedBottomType = 'trouser';

  // ==================== WOMEN'S STATE ====================
  // Shirt
  String _womenShirtSubType = 'kameez';
  final Map<String, TextEditingController> _womenShirtControllers = {};
  String _choliSleeveType = 'half';

  // Bottom
  String _womenBottomSubType = 'shalwar';
  final Map<String, TextEditingController> _womenBottomControllers = {};
  String _womenWaistband = 'naara';
  String? _elasticWidth;
  final _customElasticWidthController = TextEditingController();
  String? _beltWidth;

  // Dupatta
  bool _dupattaIncluded = false;
  bool _dupattaPico = false;
  bool _dupattaPiping = false;
  bool _dupattaLace = false;
  bool _dupattaPlain = false;
  String _picoCoverage = 'pallu_only';
  String _picoType = 'plain_pico';
  String _pipingCoverage = 'pallu_only';
  String _laceCoverage = 'pallu_only';
  bool _laceByCustomer = false;

  // Extra instructions
  List<Map<String, dynamic>> _extraInstructions = [];

  // ==================== MEN'S FIELD DEFINITIONS ====================

  static const _menShirtFields = [
    _MeasurementField(key: 'length', labelKey: 'length', urduHint: 'لمبائی'),
    _MeasurementField(key: 'shoulder', labelKey: 'shoulder_measurement', urduHint: 'کندھا'),
    _MeasurementField(key: 'chest', labelKey: 'chest_measurement', urduHint: 'چھاتی'),
    _MeasurementField(key: 'collar', labelKey: 'collar', urduHint: 'گلا'),
    _MeasurementField(key: 'sleeve_width', labelKey: 'sleeve_width', urduHint: 'آستین چوڑائی'),
    _MeasurementField(key: 'waist', labelKey: 'waist', urduHint: 'کمر'),
    _MeasurementField(key: 'hip', labelKey: 'hip', urduHint: 'کولہا'),
    _MeasurementField(key: 'sleeve', labelKey: 'sleeve', urduHint: 'آستین'),
    _MeasurementField(key: 'cuff_width', labelKey: 'cuff_width', urduHint: 'کف چوڑائی'),
    _MeasurementField(key: 'cuff_length', labelKey: 'cuff_length', urduHint: 'کف لمبائی'),
  ];

  static const _menTrouserFields = [
    _MeasurementField(key: 'trouser_length', labelKey: 'trouser_length', urduHint: 'ٹراؤزر لمبائی'),
    _MeasurementField(key: 'paincha', labelKey: 'paincha', urduHint: 'پائنچا'),
    _MeasurementField(key: 'trouser_width', labelKey: 'trouser_width', urduHint: 'گھیرا'),
    _MeasurementField(key: 'thigh', labelKey: 'thigh', urduHint: 'ران'),
    _MeasurementField(key: 'patti_width', labelKey: 'patti_width', urduHint: 'پٹی چوڑائی'),
  ];

  static const _menShalwarFields = [
    _MeasurementField(key: 'shalwar_length', labelKey: 'shalwar_length', urduHint: 'شلوار لمبائی'),
    _MeasurementField(key: 'paincha_shalwar', labelKey: 'paincha', urduHint: 'پائنچا'),
    _MeasurementField(key: 'shalwar_ghair', labelKey: 'shalwar_ghair', urduHint: 'شلوار گھیر'),
    _MeasurementField(key: 'patti_width_shalwar', labelKey: 'patti_width', urduHint: 'پٹی چوڑائی'),
  ];

  // ==================== WOMEN'S FIELD DEFINITIONS ====================

  // Kameez / Kurti (same 13 fields)
  static const _womenKameezFields = [
    _MeasurementField(key: 'w_length', labelKey: 'length', urduHint: 'لمبائی'),
    _MeasurementField(key: 'w_shoulder', labelKey: 'w_shoulder', urduHint: 'تیرہ'),
    _MeasurementField(key: 'w_sleeve', labelKey: 'w_sleeve_label', urduHint: 'بازو'),
    _MeasurementField(key: 'w_chest', labelKey: 'w_chest_label', urduHint: 'chest'),
    _MeasurementField(key: 'w_hip', labelKey: 'w_hip_label', urduHint: 'ہپ'),
    _MeasurementField(key: 'w_daman', labelKey: 'w_daman', urduHint: 'دامن'),
    _MeasurementField(key: 'w_chak', labelKey: 'w_chak', urduHint: 'چاک'),
    _MeasurementField(key: 'w_front_neck', labelKey: 'w_front_neck', urduHint: 'front گلا'),
    _MeasurementField(key: 'w_back_neck', labelKey: 'w_back_neck', urduHint: 'پچھلا گلا'),
    _MeasurementField(key: 'w_neck_width', labelKey: 'w_neck_width', urduHint: 'گلے کی چوڑائی'),
    _MeasurementField(key: 'w_kandhe_ki_chorai', labelKey: 'w_kandhe_ki_chorai', urduHint: 'کندھے کی چوڑائی'),
    _MeasurementField(key: 'w_cuff_opening', labelKey: 'w_cuff_opening', urduHint: 'بازو موری'),
    _MeasurementField(key: 'w_cuff_ki_chorai', labelKey: 'w_cuff_ki_chorai', urduHint: 'کف کی چوڑائی'),
  ];

  // Short Shirt (Kameez minus Hip and Chak)
  static const _womenShortShirtFields = [
    _MeasurementField(key: 'w_length', labelKey: 'length', urduHint: 'لمبائی'),
    _MeasurementField(key: 'w_shoulder', labelKey: 'w_shoulder', urduHint: 'تیرہ'),
    _MeasurementField(key: 'w_sleeve', labelKey: 'w_sleeve_label', urduHint: 'بازو'),
    _MeasurementField(key: 'w_chest', labelKey: 'w_chest_label', urduHint: 'chest'),
    _MeasurementField(key: 'w_daman', labelKey: 'w_daman', urduHint: 'دامن'),
    _MeasurementField(key: 'w_front_neck', labelKey: 'w_front_neck', urduHint: 'front گلا'),
    _MeasurementField(key: 'w_back_neck', labelKey: 'w_back_neck', urduHint: 'پچھلا گلا'),
    _MeasurementField(key: 'w_neck_width', labelKey: 'w_neck_width', urduHint: 'گلے کی چوڑائی'),
    _MeasurementField(key: 'w_kandhe_ki_chorai', labelKey: 'w_kandhe_ki_chorai', urduHint: 'کندھے کی چوڑائی'),
    _MeasurementField(key: 'w_cuff_opening', labelKey: 'w_cuff_opening', urduHint: 'بازو موری'),
    _MeasurementField(key: 'w_cuff_ki_chorai', labelKey: 'w_cuff_ki_chorai', urduHint: 'کف کی چوڑائی'),
  ];

  // Choli (different set, 11 fields + sleeve handled separately)
  static const _womenCholiFields = [
    _MeasurementField(key: 'w_choli_length', labelKey: 'choli_length', urduHint: 'چولی کی لمبائی'),
    _MeasurementField(key: 'w_choli_shoulder', labelKey: 'w_choli_shoulder', urduHint: 'تیرا'),
    _MeasurementField(key: 'w_choli_chest', labelKey: 'w_choli_chest', urduHint: 'چیسٹ'),
    _MeasurementField(key: 'w_under_bust', labelKey: 'under_bust', urduHint: 'انڈر بسٹ'),
    _MeasurementField(key: 'w_choli_front_neck', labelKey: 'w_front_neck', urduHint: 'front گلا'),
    _MeasurementField(key: 'w_choli_back_neck', labelKey: 'w_back_neck', urduHint: 'پچھلا گلا'),
    _MeasurementField(key: 'w_choli_neck_width', labelKey: 'w_neck_width', urduHint: 'گلے کی چوڑائی'),
    _MeasurementField(key: 'w_choli_kandhe_ki_chaurai', labelKey: 'w_kandhe_ki_chorai', urduHint: 'کندھے کی چوڑائی'),
    _MeasurementField(key: 'w_sleeve_opening', labelKey: 'sleeve_opening', urduHint: 'بازو موری'),
    _MeasurementField(key: 'w_sleeve_opening_width', labelKey: 'sleeve_opening_width', urduHint: 'موری کی چوڑائی'),
    _MeasurementField(key: 'w_waist_band', labelKey: 'waist_band_measurement', urduHint: 'کمر پٹی'),
  ];

  // Women's bottom sub-type fields
  static const _womenShalwarFields = [
    _MeasurementField(key: 'w_shalwar_length', labelKey: 'shalwar_length', urduHint: 'شلوار لمبائی'),
    _MeasurementField(key: 'w_front_asan', labelKey: 'front_asan', urduHint: 'آسن'),
    _MeasurementField(key: 'w_back_asan', labelKey: 'back_asan', urduHint: 'پچھلا آسن'),
    _MeasurementField(key: 'w_thigh', labelKey: 'thigh', urduHint: 'ران'),
    _MeasurementField(key: 'w_paincha', labelKey: 'paincha', urduHint: 'پانچہ'),
    _MeasurementField(key: 'w_ghera', labelKey: 'ghera', urduHint: 'گھیرا'),
  ];

  static const _womenTrouserFields = [
    _MeasurementField(key: 'w_trouser_length', labelKey: 'trouser_length', urduHint: 'ٹراؤزر لمبائی'),
    _MeasurementField(key: 'w_front_asan', labelKey: 'front_asan', urduHint: 'آسن'),
    _MeasurementField(key: 'w_back_asan', labelKey: 'back_asan', urduHint: 'پچھلا آسن'),
    _MeasurementField(key: 'w_thigh', labelKey: 'thigh', urduHint: 'ران'),
    _MeasurementField(key: 'w_paincha', labelKey: 'paincha', urduHint: 'پانچہ'),
  ];

  static const _womenPajamaFields = [
    _MeasurementField(key: 'w_pajama_length', labelKey: 'pajama_length', urduHint: 'پاجامہ لمبائی'),
    _MeasurementField(key: 'w_front_asan', labelKey: 'front_asan', urduHint: 'آسن'),
    _MeasurementField(key: 'w_back_asan', labelKey: 'back_asan', urduHint: 'پچھلا آسن'),
    _MeasurementField(key: 'w_paincha', labelKey: 'paincha', urduHint: 'پانچہ'),
    _MeasurementField(key: 'w_thigh', labelKey: 'thigh', urduHint: 'ران'),
  ];

  static const _womenShararaFields = [
    _MeasurementField(key: 'w_sharara_length', labelKey: 'sharara_length', urduHint: 'شرارہ لمبائی'),
    _MeasurementField(key: 'w_front_asan', labelKey: 'front_asan', urduHint: 'آسن'),
    _MeasurementField(key: 'w_back_asan', labelKey: 'back_asan', urduHint: 'پچھلا آسن'),
    _MeasurementField(key: 'w_ghera', labelKey: 'ghera', urduHint: 'گھیرا'),
  ];

  static const _womenGhararaFields = [
    _MeasurementField(key: 'w_gharara_length', labelKey: 'gharara_length', urduHint: 'غرارہ لمبائی'),
    _MeasurementField(key: 'w_front_asan', labelKey: 'front_asan', urduHint: 'آسن'),
    _MeasurementField(key: 'w_back_asan', labelKey: 'back_asan', urduHint: 'پچھلا آسن'),
    _MeasurementField(key: 'w_ghutna', labelKey: 'ghutna', urduHint: 'گھٹنا'),
    _MeasurementField(key: 'w_ghera', labelKey: 'ghera', urduHint: 'گھیرا'),
  ];

  // ==================== WAISTBAND HELPERS ====================

  static const _waistbandUrdu = {
    'naara': 'نارا',
    'elastic': 'الاسٹک',
    'naara_elastic': 'نارا + الاسٹک',
    'belt': 'بیلٹ',
    'full_belt': 'فل بیلٹ',
    'half_belt': 'ہاف بیلٹ',
  };

  static const _dupattaUrdu = {
    'pico': 'پیکو',
    'piping': 'پائپنگ',
    'lace': 'لیس',
    'plain_no_finishing': 'سادہ',
    'pallu_only': 'صرف پلو',
    'all_around': 'چاروں طرف',
    'plain_pico': 'سادہ پیکو',
    'japanese_pico': 'جاپانی پیکو',
  };

  List<(String value, String labelKey)> _getWaistbandOptions() {
    switch (_womenBottomSubType) {
      case 'shalwar':
        return [('naara', 'naara'), ('elastic', 'elastic'), ('naara_elastic', 'naara_elastic'), ('belt', 'belt')];
      case 'trouser':
        return [('full_belt', 'full_belt'), ('half_belt', 'half_belt'), ('elastic', 'elastic')];
      case 'pajama':
        return [('naara', 'naara'), ('elastic', 'elastic'), ('naara_elastic', 'naara_elastic')];
      case 'sharara':
        return [('elastic', 'elastic'), ('naara', 'naara'), ('belt', 'belt')];
      case 'gharara':
        return [('belt', 'belt'), ('elastic', 'elastic'), ('naara', 'naara')];
      default:
        return [];
    }
  }

  String _defaultWaistband(String bottomType) {
    switch (bottomType) {
      case 'shalwar': return 'naara';
      case 'trouser': return 'full_belt';
      case 'pajama': return 'naara';
      case 'sharara': return 'elastic';
      case 'gharara': return 'belt';
      default: return 'naara';
    }
  }

  bool get _needsElasticWidth =>
      _womenWaistband == 'elastic' || _womenWaistband == 'naara_elastic';

  bool get _needsBeltWidth =>
      _womenBottomSubType == 'gharara' && _womenWaistband == 'belt';

  // ==================== WOMEN'S FIELD GETTERS ====================

  List<_MeasurementField> get _currentWomenShirtFields {
    switch (_womenShirtSubType) {
      case 'kameez':
      case 'kurti':
        return _womenKameezFields;
      case 'short_shirt':
        return _womenShortShirtFields;
      case 'choli':
        return _womenCholiFields;
      default:
        return _womenKameezFields;
    }
  }

  List<_MeasurementField> get _currentWomenBottomFields {
    switch (_womenBottomSubType) {
      case 'shalwar': return _womenShalwarFields;
      case 'trouser': return _womenTrouserFields;
      case 'pajama': return _womenPajamaFields;
      case 'sharara': return _womenShararaFields;
      case 'gharara': return _womenGhararaFields;
      default: return _womenShalwarFields;
    }
  }

  // ==================== LIFECYCLE ====================

  @override
  void initState() {
    super.initState();
    _menBottomTabController = TabController(length: 2, vsync: this);
    _menBottomTabController.addListener(() {
      if (!_menBottomTabController.indexIsChanging) {
        setState(() {
          _menSelectedBottomType =
              _menBottomTabController.index == 0 ? 'trouser' : 'shalwar';
        });
      }
    });

    _initControllers();
    _prefillFromSaved();

    if (!_isNaapSuit) {
      _shirtExpanded = true;
      _bottomExpanded = true;
    }
  }

  void _initControllers() {
    // Men's controllers
    for (final f in _menShirtFields) {
      _menShirtControllers[f.key] = TextEditingController();
    }
    for (final f in _menTrouserFields) {
      _menBottomControllers[f.key] = TextEditingController();
    }
    for (final f in _menShalwarFields) {
      _menBottomControllers[f.key] = TextEditingController();
    }

    // Women's shirt controllers (union of all sub-types)
    for (final list in [_womenKameezFields, _womenCholiFields]) {
      for (final f in list) {
        _womenShirtControllers.putIfAbsent(f.key, () => TextEditingController());
      }
    }
    // Choli sleeve length
    _womenShirtControllers.putIfAbsent(
        'w_choli_sleeve_length', () => TextEditingController());

    // Women's bottom controllers (union of all sub-types)
    for (final list in [
      _womenShalwarFields,
      _womenTrouserFields,
      _womenPajamaFields,
      _womenShararaFields,
      _womenGhararaFields,
    ]) {
      for (final f in list) {
        _womenBottomControllers.putIfAbsent(
            f.key, () => TextEditingController());
      }
    }
  }

  void _prefillFromSaved() {
    if (widget.savedMeasurements == null) return;

    for (final m in widget.savedMeasurements!) {
      final data = m.measurements;
      final options = m.additionalOptions != null
          ? json.decode(m.additionalOptions!) as Map<String, dynamic>
          : <String, dynamic>{};

      if (m.garmentType == 'shirt') {
        if (_isMale) {
          for (final entry in data.entries) {
            if (_menShirtControllers.containsKey(entry.key)) {
              _menShirtControllers[entry.key]!.text = entry.value.toString();
            }
          }
          _collarNok = options['collar_nok'] == true;
          _collarBan = options['collar_ban'] == true;
          _sidePocket = options['side_pocket'] ?? 'none';
          _frontPocket = options['front_pocket'] == true;
        } else {
          final subType = options['shirt_sub_type'] ?? 'kameez';
          _womenShirtSubType = subType;
          for (final entry in data.entries) {
            if (_womenShirtControllers.containsKey(entry.key)) {
              _womenShirtControllers[entry.key]!.text =
                  entry.value.toString();
            }
          }
          if (subType == 'choli') {
            _choliSleeveType = options['sleeve_type'] ?? 'half';
          }
        }
      } else if (m.garmentType == 'shalwar_trouser') {
        final bottomType = options['bottom_type'] ?? 'trouser';
        if (_isMale) {
          if (bottomType == 'shalwar') {
            _menBottomTabController.index = 1;
            _menSelectedBottomType = 'shalwar';
          }
          for (final entry in data.entries) {
            if (_menBottomControllers.containsKey(entry.key)) {
              _menBottomControllers[entry.key]!.text = entry.value.toString();
            }
          }
          _trouserPocket = options['trouser_pocket'] == true;
          _shalwarPocket = options['shalwar_pocket'] == true;
        } else {
          _womenBottomSubType = bottomType;
          _womenWaistband =
              options['waistband'] ?? _defaultWaistband(bottomType);
          if (options['elastic_width'] != null) {
            final ew = options['elastic_width'].toString();
            if (['1', '1.5', '2'].contains(ew)) {
              _elasticWidth = ew;
            } else {
              _elasticWidth = 'custom';
              _customElasticWidthController.text = ew;
            }
          }
          if (options['belt_width'] != null) {
            _beltWidth = options['belt_width'].toString();
          }
          for (final entry in data.entries) {
            if (_womenBottomControllers.containsKey(entry.key)) {
              _womenBottomControllers[entry.key]!.text =
                  entry.value.toString();
            }
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _menBottomTabController.dispose();
    for (final c in _menShirtControllers.values) {
      c.dispose();
    }
    for (final c in _menBottomControllers.values) {
      c.dispose();
    }
    for (final c in _womenShirtControllers.values) {
      c.dispose();
    }
    for (final c in _womenBottomControllers.values) {
      c.dispose();
    }
    _customElasticWidthController.dispose();
    super.dispose();
  }

  // ==================== DATA COLLECTION ====================

  // --- Men ---
  Map<String, dynamic> _collectMenShirtData() {
    final data = <String, dynamic>{};
    for (final f in _menShirtFields) {
      final val = _menShirtControllers[f.key]!.text.trim();
      if (val.isNotEmpty) data[f.key] = double.tryParse(val) ?? val;
    }
    return data;
  }

  Map<String, dynamic> _collectMenShirtOptions() => {
        'collar_nok': _collarNok,
        'collar_ban': _collarBan,
        'side_pocket': _sidePocket,
        'front_pocket': _frontPocket,
      };

  Map<String, dynamic> _collectMenBottomData() {
    final fields = _menSelectedBottomType == 'trouser'
        ? _menTrouserFields
        : _menShalwarFields;
    final data = <String, dynamic>{};
    for (final f in fields) {
      final val = _menBottomControllers[f.key]!.text.trim();
      if (val.isNotEmpty) data[f.key] = double.tryParse(val) ?? val;
    }
    return data;
  }

  Map<String, dynamic> _collectMenBottomOptions() => {
        'bottom_type': _menSelectedBottomType,
        'trouser_pocket': _trouserPocket,
        'shalwar_pocket': _shalwarPocket,
      };

  // --- Women ---
  Map<String, dynamic> _collectWomenShirtData() {
    final data = <String, dynamic>{};
    for (final f in _currentWomenShirtFields) {
      final val = _womenShirtControllers[f.key]?.text.trim() ?? '';
      if (val.isNotEmpty) data[f.key] = double.tryParse(val) ?? val;
    }
    if (_womenShirtSubType == 'choli' && _choliSleeveType != 'sleeveless') {
      final val =
          _womenShirtControllers['w_choli_sleeve_length']?.text.trim() ?? '';
      if (val.isNotEmpty) {
        data['w_choli_sleeve_length'] = double.tryParse(val) ?? val;
      }
    }
    return data;
  }

  Map<String, dynamic> _collectWomenShirtOptions() {
    final opts = <String, dynamic>{'shirt_sub_type': _womenShirtSubType};
    if (_womenShirtSubType == 'choli') {
      opts['sleeve_type'] = _choliSleeveType;
    }
    return opts;
  }

  Map<String, dynamic> _collectWomenBottomData() {
    final data = <String, dynamic>{};
    for (final f in _currentWomenBottomFields) {
      final val = _womenBottomControllers[f.key]?.text.trim() ?? '';
      if (val.isNotEmpty) data[f.key] = double.tryParse(val) ?? val;
    }
    return data;
  }

  Map<String, dynamic> _collectWomenBottomOptions() {
    final opts = <String, dynamic>{
      'bottom_type': _womenBottomSubType,
      'waistband': _womenWaistband,
    };
    if (_needsElasticWidth && _elasticWidth != null) {
      opts['elastic_width'] = _elasticWidth == 'custom'
          ? _customElasticWidthController.text.trim()
          : _elasticWidth;
    }
    if (_needsBeltWidth && _beltWidth != null) {
      opts['belt_width'] = _beltWidth;
    }
    return opts;
  }

  Map<String, dynamic>? _collectDupattaData() {
    if (!_showDupatta || !_dupattaIncluded) return null;
    final finishing = <String>[];
    if (_dupattaPico) finishing.add('pico');
    if (_dupattaPiping) finishing.add('piping');
    if (_dupattaLace) finishing.add('lace');
    if (_dupattaPlain) finishing.add('plain');
    return {
      'included': true,
      'finishing': finishing.join(','),
      'pico_coverage': _dupattaPico ? _picoCoverage : null,
      'pico_type': _dupattaPico ? _picoType : null,
      'piping_coverage': _dupattaPiping ? _pipingCoverage : null,
      'lace_coverage': _dupattaLace ? _laceCoverage : null,
      'lace_provided_by_customer': _dupattaLace ? _laceByCustomer : false,
    };
  }

  // ==================== ON NEXT ====================

  Future<void> _onNext() async {
    final shirtData =
        _showShirt ? (_isMale ? _collectMenShirtData() : _collectWomenShirtData()) : <String, dynamic>{};
    final shirtOptions =
        _showShirt ? (_isMale ? _collectMenShirtOptions() : _collectWomenShirtOptions()) : <String, dynamic>{};
    final bottomData =
        _showBottom ? (_isMale ? _collectMenBottomData() : _collectWomenBottomData()) : <String, dynamic>{};
    final bottomOptions =
        _showBottom ? (_isMale ? _collectMenBottomOptions() : _collectWomenBottomOptions()) : <String, dynamic>{};
    final dupatta = _collectDupattaData();

    // Determine sub-types
    String? shirtSubType;
    if (_isFemale && _showShirt) {
      shirtSubType = _womenShirtSubType;
    }
    String? bottomType;
    if (_showBottom) {
      bottomType = _isMale ? _menSelectedBottomType : _womenBottomSubType;
    }
    String? waistband;
    String? elasticWidth;
    if (_isFemale && _showBottom) {
      waistband = _womenWaistband;
      if (_needsElasticWidth && _elasticWidth != null) {
        elasticWidth = _elasticWidth == 'custom'
            ? _customElasticWidthController.text.trim()
            : _elasticWidth;
      }
    }

    if (!mounted) return;

    Navigator.of(context).push(
      SlidePageRoute(
        page: OrderDetailsScreen(
          customerId: widget.customerId,
          customerName: widget.customerName,
          customerPhone: widget.customerPhone,
          customerGender: widget.customerGender,
          customerSerialNumber: widget.customerSerialNumber,
          stitchType: widget.stitchType,
          shirtSubType: shirtSubType,
          bottomType: bottomType,
          bottomWaistband: waistband,
          elasticWidth: elasticWidth,
          shirtMeasurementData: shirtData,
          shirtAdditionalOptions: shirtOptions,
          bottomMeasurementData: bottomData,
          bottomAdditionalOptions: bottomOptions,
          dupattaDetails: dupatta,
          extraInstructions: _extraInstructions,
        ),
      ),
    );
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('measurements'.tr(),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            Text(
              '${widget.customerName} (#${widget.customerSerialNumber})',
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: Column(
                  children: [
                    if (_showShirt)
                      _isMale
                          ? _buildMenShirtSection()
                          : _buildWomenShirtSection(),
                    if (_showShirt && _showBottom)
                      const SizedBox(height: 20),
                    if (_showBottom)
                      _isMale
                          ? _buildMenBottomSection()
                          : _buildWomenBottomSection(),
                    if (_showDupatta) ...[
                      const SizedBox(height: 20),
                      _buildDupattaSection(),
                    ],
                    const SizedBox(height: 20),
                    ExtraInstructionsWidget(
                      titleTranslationKey: 'extra_instructions',
                      initialInstructions: _extraInstructions.isNotEmpty
                          ? _extraInstructions
                          : null,
                      onChanged: (instructions) {
                        _extraInstructions = instructions;
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            _buildNextButton(),
          ],
        ),
      ),
    );
  }

  // ==================== MEN'S SHIRT SECTION ====================

  Widget _buildMenShirtSection() {
    final content = Column(
      children: [
        _buildMeasurementGrid(_menShirtFields, _menShirtControllers),
        const SizedBox(height: 16),
        _buildMenShirtOptions(),
      ],
    );

    if (_isNaapSuit) {
      return _buildSectionHeader(
        icon: Icons.checkroom,
        title: 'shirt_kameez'.tr(),
        expanded: _shirtExpanded,
        onTap: () => setState(() => _shirtExpanded = !_shirtExpanded),
        child: _shirtExpanded ? content : null,
      );
    }

    return _buildSectionHeader(
      icon: Icons.checkroom,
      title: 'shirt_kameez'.tr(),
      expanded: true,
      onTap: null,
      child: content,
    );
  }

  Widget _buildMenShirtOptions() {
    return Column(
      children: [
        _buildToggleRow(
          label: 'collar_nok'.tr(),
          value: _collarNok,
          onChanged: (v) => setState(() => _collarNok = v),
        ),
        const SizedBox(height: 8),
        _buildToggleRow(
          label: 'collar_ban'.tr(),
          value: _collarBan,
          onChanged: (v) => setState(() => _collarBan = v),
        ),
        const SizedBox(height: 12),
        _buildSidePocketSelector(),
        const SizedBox(height: 8),
        _buildToggleRow(
          label: 'front_pocket'.tr(),
          value: _frontPocket,
          onChanged: (v) => setState(() => _frontPocket = v),
        ),
      ],
    );
  }

  Widget _buildSidePocketSelector() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            'side_pocket'.tr(),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Row(
            children: [
              _buildSidePocketChip('none', 'none'.tr()),
              const SizedBox(width: 6),
              _buildSidePocketChip('one_side', 'one_side'.tr()),
              const SizedBox(width: 6),
              _buildSidePocketChip('both_sides', 'both_sides'.tr()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSidePocketChip(String value, String label) {
    final selected = _sidePocket == value;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _sidePocket = value),
          borderRadius: BorderRadius.circular(8),
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : AppColors.cardBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
              ),
            ),
            child: Text(
              label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
          ),
          ),
        ),
      ),
    );
  }

  // ==================== MEN'S BOTTOM SECTION ====================

  Widget _buildMenBottomSection() {
    final content = Column(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(10),
          ),
          child: TabBar(
            controller: _menBottomTabController,
            indicator: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            labelColor: Colors.white,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            tabs: [
              Tab(text: 'trouser'.tr()),
              Tab(text: 'shalwar'.tr()),
            ],
          ),
        ),
        if (_menSelectedBottomType == 'trouser') ...[
          _buildMeasurementGrid(_menTrouserFields, _menBottomControllers),
          const SizedBox(height: 12),
          _buildToggleRow(
            label: '${'pocket'.tr()} (${'trouser'.tr()})',
            value: _trouserPocket,
            onChanged: (v) => setState(() => _trouserPocket = v),
          ),
        ] else ...[
          _buildMeasurementGrid(_menShalwarFields, _menBottomControllers),
          const SizedBox(height: 12),
          _buildToggleRow(
            label: '${'pocket'.tr()} (${'shalwar'.tr()})',
            value: _shalwarPocket,
            onChanged: (v) => setState(() => _shalwarPocket = v),
          ),
        ],
      ],
    );

    if (_isNaapSuit) {
      return _buildSectionHeader(
        icon: Icons.straighten,
        title: '${'trouser'.tr()} / ${'shalwar'.tr()}',
        expanded: _bottomExpanded,
        onTap: () => setState(() => _bottomExpanded = !_bottomExpanded),
        child: _bottomExpanded ? content : null,
      );
    }

    return _buildSectionHeader(
      icon: Icons.straighten,
      title: '${'trouser'.tr()} / ${'shalwar'.tr()}',
      expanded: true,
      onTap: null,
      child: content,
    );
  }

  // ==================== WOMEN'S SHIRT SECTION ====================

  Widget _buildWomenShirtSection() {
    final content = Column(
      children: [
        _buildSubTypeSelector(
          options: [
            ('kameez', 'kameez'),
            ('kurti', 'kurti'),
            ('short_shirt', 'short_shirt'),
            ('choli', 'choli'),
          ],
          selected: _womenShirtSubType,
          onSelected: (v) => setState(() => _womenShirtSubType = v),
        ),
        const SizedBox(height: 14),
        _buildMeasurementGrid(
            _currentWomenShirtFields, _womenShirtControllers),
        if (_womenShirtSubType == 'choli') ...[
          const SizedBox(height: 14),
          _buildCholiSleeveSection(),
        ],
      ],
    );

    if (_isNaapSuit) {
      return _buildSectionHeader(
        icon: Icons.checkroom,
        title: 'shirt_kameez'.tr(),
        expanded: _shirtExpanded,
        onTap: () => setState(() => _shirtExpanded = !_shirtExpanded),
        child: _shirtExpanded ? content : null,
      );
    }

    return _buildSectionHeader(
      icon: Icons.checkroom,
      title: 'shirt_kameez'.tr(),
      expanded: true,
      onTap: null,
      child: content,
    );
  }

  Widget _buildCholiSleeveSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'sleeve_length_label'.tr(),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildSelectableChip(
              label: 'half_sleeve'.tr(),
              selected: _choliSleeveType == 'half',
              onTap: () => setState(() => _choliSleeveType = 'half'),
            ),
            const SizedBox(width: 8),
            _buildSelectableChip(
              label: 'full_sleeve'.tr(),
              selected: _choliSleeveType == 'full',
              onTap: () => setState(() => _choliSleeveType = 'full'),
            ),
            const SizedBox(width: 8),
            _buildSelectableChip(
              label: 'sleeveless'.tr(),
              selected: _choliSleeveType == 'sleeveless',
              onTap: () => setState(() => _choliSleeveType = 'sleeveless'),
            ),
          ],
        ),
        if (_choliSleeveType != 'sleeveless') ...[
          const SizedBox(height: 10),
          SizedBox(
            width: 160,
            child: _buildMeasurementField(
              const _MeasurementField(
                key: 'w_choli_sleeve_length',
                labelKey: 'sleeve_length_label',
                urduHint: 'بازو لمبائی',
              ),
              _womenShirtControllers['w_choli_sleeve_length']!,
            ),
          ),
        ],
      ],
    );
  }

  // ==================== WOMEN'S BOTTOM SECTION ====================

  Widget _buildWomenBottomSection() {
    final content = Column(
      children: [
        _buildSubTypeSelector(
          options: [
            ('shalwar', 'shalwar'),
            ('trouser', 'trouser'),
            ('pajama', 'pajama'),
            ('sharara', 'sharara'),
            ('gharara', 'gharara'),
          ],
          selected: _womenBottomSubType,
          onSelected: (v) {
            setState(() {
              _womenBottomSubType = v;
              _womenWaistband = _defaultWaistband(v);
              _elasticWidth = null;
              _beltWidth = null;
              _customElasticWidthController.clear();
            });
          },
        ),
        const SizedBox(height: 14),
        _buildMeasurementGrid(
            _currentWomenBottomFields, _womenBottomControllers),
        const SizedBox(height: 16),
        _buildWaistbandSelector(),
      ],
    );

    final title = '${'shalwar'.tr()} / ${'trouser'.tr()}';

    if (_isNaapSuit) {
      return _buildSectionHeader(
        icon: Icons.straighten,
        title: title,
        expanded: _bottomExpanded,
        onTap: () => setState(() => _bottomExpanded = !_bottomExpanded),
        child: _bottomExpanded ? content : null,
      );
    }

    return _buildSectionHeader(
      icon: Icons.straighten,
      title: title,
      expanded: true,
      onTap: null,
      child: content,
    );
  }

  Widget _buildWaistbandSelector() {
    final options = _getWaistbandOptions();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'waistband'.tr(),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((o) {
            final urdu = _waistbandUrdu[o.$1];
            final label = urdu != null ? '${o.$2.tr()} ($urdu)' : o.$2.tr();
            return _buildSelectableChip(
              label: label,
              selected: _womenWaistband == o.$1,
              onTap: () => setState(() {
                _womenWaistband = o.$1;
                if (!_needsElasticWidth) _elasticWidth = null;
                if (!_needsBeltWidth) _beltWidth = null;
              }),
            );
          }).toList(),
        ),
        if (_needsElasticWidth) ...[
          const SizedBox(height: 12),
          _buildWidthChooser(
            label: 'elastic_width_label'.tr(),
            value: _elasticWidth,
            showCustom: true,
            onChanged: (v) => setState(() => _elasticWidth = v),
          ),
        ],
        if (_needsBeltWidth) ...[
          const SizedBox(height: 12),
          _buildWidthChooser(
            label: 'belt_width_label'.tr(),
            value: _beltWidth,
            showCustom: false,
            onChanged: (v) => setState(() => _beltWidth = v),
          ),
        ],
      ],
    );
  }

  Widget _buildWidthChooser({
    required String label,
    required String? value,
    required bool showCustom,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in ['1', '1.5', '2'])
              _buildSelectableChip(
                label: '$p"',
                selected: value == p,
                onTap: () => onChanged(p),
              ),
            if (showCustom)
              _buildSelectableChip(
                label: 'custom'.tr(),
                selected: value == 'custom',
                onTap: () => onChanged('custom'),
              ),
          ],
        ),
        if (showCustom && value == 'custom') ...[
          const SizedBox(height: 8),
          SizedBox(
            width: 120,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: TextFormField(
                controller: _customElasticWidthController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(
                    fontSize: 15, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'inches'.tr(),
                  hintStyle: const TextStyle(
                      fontSize: 13, color: AppColors.textHint),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ==================== DUPATTA SECTION ====================

  Widget _buildDupattaSection() {
    return _buildSectionHeader(
      icon: Icons.auto_awesome,
      title: 'dupatta'.tr(),
      expanded: true,
      onTap: null,
      child: Column(
        children: [
          _buildToggleRow(
            label: 'dupatta_included'.tr(),
            value: _dupattaIncluded,
            onChanged: (v) => setState(() => _dupattaIncluded = v),
          ),
          if (_dupattaIncluded) ...[
            const SizedBox(height: 12),
            _buildDupattaFinishing(),
          ],
        ],
      ),
    );
  }

  Widget _buildDupattaFinishing() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'finishing'.tr(),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        // Checkboxes
        _buildCheckboxRow('${'pico'.tr()} (${_dupattaUrdu['pico']})', _dupattaPico, (v) {
          setState(() {
            _dupattaPico = v;
            if (v) _dupattaPlain = false;
          });
        }),
        _buildCheckboxRow('${'piping'.tr()} (${_dupattaUrdu['piping']})', _dupattaPiping, (v) {
          setState(() {
            _dupattaPiping = v;
            if (v) _dupattaPlain = false;
          });
        }),
        _buildCheckboxRow('${'lace'.tr()} (${_dupattaUrdu['lace']})', _dupattaLace, (v) {
          setState(() {
            _dupattaLace = v;
            if (v) _dupattaPlain = false;
          });
        }),
        _buildCheckboxRow('${'plain_no_finishing'.tr()} (${_dupattaUrdu['plain_no_finishing']})', _dupattaPlain, (v) {
          setState(() {
            _dupattaPlain = v;
            if (v) {
              _dupattaPico = false;
              _dupattaPiping = false;
              _dupattaLace = false;
            }
          });
        }),

        // Pico sub-options
        if (_dupattaPico) ...[
          const SizedBox(height: 12),
          _buildDupattaSubOption(
            title: '${'pico'.tr()} — ${'coverage'.tr()}',
            options: [('pallu_only', 'pallu_only'), ('all_around', 'all_around')],
            selected: _picoCoverage,
            onSelected: (v) => setState(() => _picoCoverage = v),
          ),
          const SizedBox(height: 8),
          _buildDupattaSubOption(
            title: '${'pico'.tr()} — ${'type_label'.tr()}',
            options: [('plain_pico', 'plain_pico'), ('japanese_pico', 'japanese_pico')],
            selected: _picoType,
            onSelected: (v) => setState(() => _picoType = v),
          ),
        ],

        // Piping sub-options
        if (_dupattaPiping) ...[
          const SizedBox(height: 12),
          _buildDupattaSubOption(
            title: '${'piping'.tr()} — ${'coverage'.tr()}',
            options: [('pallu_only', 'pallu_only'), ('all_around', 'all_around')],
            selected: _pipingCoverage,
            onSelected: (v) => setState(() => _pipingCoverage = v),
          ),
        ],

        // Lace sub-options
        if (_dupattaLace) ...[
          const SizedBox(height: 12),
          _buildDupattaSubOption(
            title: '${'lace'.tr()} — ${'coverage'.tr()}',
            options: [('pallu_only', 'pallu_only'), ('all_around', 'all_around')],
            selected: _laceCoverage,
            onSelected: (v) => setState(() => _laceCoverage = v),
          ),
          const SizedBox(height: 8),
          _buildToggleRow(
            label: 'lace_provided_by_customer'.tr(),
            value: _laceByCustomer,
            onChanged: (v) => setState(() => _laceByCustomer = v),
          ),
        ],
      ],
    );
  }

  Widget _buildCheckboxRow(
      String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDupattaSubOption({
    required String title,
    required List<(String value, String labelKey)> options,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: options.map((o) {
            final urdu = _dupattaUrdu[o.$1];
            final label = urdu != null ? '${o.$2.tr()} ($urdu)' : o.$2.tr();
            return _buildSelectableChip(
              label: label,
              selected: selected == o.$1,
              onTap: () => onSelected(o.$1),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ==================== SHARED WIDGETS ====================

  Widget _buildSubTypeSelector({
    required List<(String value, String labelKey)> options,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((o) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _buildSelectableChip(
              label: o.$2.tr(),
              selected: selected == o.$1,
              onTap: () => onSelected(o.$1),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSelectableChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required bool expanded,
    required VoidCallback? onTap,
    Widget? child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: AppColors.primary,
                    width: 4,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.dashboardAccent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child:
                        Icon(icon, size: 22, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (onTap != null)
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: AppColors.textSecondary,
                    ),
                ],
              ),
            ),
          ),
          if (child != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: child,
            ),
        ],
      ),
    );
  }

  Widget _buildMeasurementGrid(
    List<_MeasurementField> fields,
    Map<String, TextEditingController> controllers,
  ) {
    final rows = <Widget>[];
    for (var i = 0; i < fields.length; i += 2) {
      final first = fields[i];
      final second = i + 1 < fields.length ? fields[i + 1] : null;
      rows.add(
        Row(
          children: [
            Expanded(
              child:
                  _buildMeasurementField(first, controllers[first.key]!),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: second != null
                  ? _buildMeasurementField(
                      second, controllers[second.key]!)
                  : const SizedBox(),
            ),
          ],
        ),
      );
      if (i + 2 < fields.length) rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }

  Widget _buildMeasurementField(
    _MeasurementField field,
    TextEditingController controller,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field.labelKey.tr(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          TextFormField(
            controller: controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: field.urduHint,
              hintStyle: const TextStyle(
                fontSize: 13,
                fontFamily: 'NotoNastaliqUrdu',
                color: AppColors.textHint,
              ),
              suffixText: 'inches'.tr(),
              suffixStyle: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 6),
              border: InputBorder.none,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.primary,
          activeTrackColor: AppColors.primaryLight,
        ),
      ],
    );
  }

  Widget _buildNextButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDark],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: ElevatedButton(
            onPressed: _onNext,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              'next'.tr(),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MeasurementField {
  final String key;
  final String labelKey;
  final String urduHint;

  const _MeasurementField({
    required this.key,
    required this.labelKey,
    required this.urduHint,
  });
}
