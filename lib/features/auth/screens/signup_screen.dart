import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/page_transitions.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../providers/auth_service.dart';
import 'otp_screen.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ownerNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _shopNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();
  final List<FocusNode> _focusNodes = List.generate(7, (_) => FocusNode());
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _ownerNameController.dispose();
    _phoneController.dispose();
    _shopNameController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _focusNext(int currentIndex) {
    if (currentIndex + 1 < _focusNodes.length) {
      FocusScope.of(context).requestFocus(_focusNodes[currentIndex + 1]);
    }
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final result = await _authService.signUp(
      _emailController.text.trim(),
      _passwordController.text,
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result['success']) {
      Navigator.of(context).push(
        SlidePageRoute(
          page: OtpScreen(
            email: _emailController.text.trim(),
            ownerName: _ownerNameController.text.trim(),
            phone: _phoneController.text.trim(),
            shopName: _shopNameController.text.trim(),
            address: _addressController.text.trim(),
          ),
        ),
      );
    } else {
      SnackbarHelper.showError(context, result['message']);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 30),

                // Header
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.content_cut,
                          size: 35,
                          color: AppColors.textOnPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'sign_up'.tr(),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'create_your_account'.tr(),
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // Owner Name
                _buildLabel('owner_name'.tr()),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _ownerNameController,
                  focusNode: _focusNodes[0],
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _focusNext(0),
                  decoration: InputDecoration(
                    hintText: 'owner_name'.tr(),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'error_required_field'.tr();
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 14),

                // Phone Number
                _buildLabel('phone_number'.tr()),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _phoneController,
                  focusNode: _focusNodes[1],
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _focusNext(1),
                  decoration: const InputDecoration(
                    hintText: '03XX XXXXXXX',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'error_required_field'.tr();
                    }
                    if (value.trim().length < 10) {
                      return 'error_invalid_phone'.tr();
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 14),

                // Shop Name
                _buildLabel('shop_name'.tr()),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _shopNameController,
                  focusNode: _focusNodes[2],
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _focusNext(2),
                  decoration: InputDecoration(
                    hintText: 'shop_name'.tr(),
                    prefixIcon: const Icon(Icons.store_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'error_required_field'.tr();
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 14),

                // Shop Address
                _buildLabel('shop_address'.tr()),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _addressController,
                  focusNode: _focusNodes[3],
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _focusNext(3),
                  decoration: InputDecoration(
                    hintText: 'shop_address'.tr(),
                    prefixIcon: const Icon(Icons.location_on_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'error_required_field'.tr();
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 14),

                // Email
                _buildLabel('email'.tr()),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _emailController,
                  focusNode: _focusNodes[4],
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _focusNext(4),
                  decoration: const InputDecoration(
                    hintText: 'example@email.com',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'error_required_field'.tr();
                    }
                    if (!value.contains('@') || !value.contains('.')) {
                      return 'error_invalid_email'.tr();
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 14),

                // Password
                _buildLabel('password'.tr()),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _passwordController,
                  focusNode: _focusNodes[5],
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _focusNext(5),
                  decoration: InputDecoration(
                    hintText: 'password_hint'.tr(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'error_required_field'.tr();
                    }
                    if (value.length < 6) {
                      return 'error_password_short'.tr();
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 14),

                // Confirm Password
                _buildLabel('confirm_password'.tr()),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _confirmPasswordController,
                  focusNode: _focusNodes[6],
                  obscureText: _obscureConfirmPassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) {
                    if (!_isLoading) _handleSignup();
                  },
                  decoration: InputDecoration(
                    hintText: 'confirm_password'.tr(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () {
                        setState(() =>
                            _obscureConfirmPassword = !_obscureConfirmPassword);
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'error_required_field'.tr();
                    }
                    if (value != _passwordController.text) {
                      return 'error_password_mismatch'.tr();
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 28),

                // Sign Up Button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleSignup,
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: AppColors.textOnPrimary,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text(
                            'sign_up'.tr(),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 12),

                // Already have account
                Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        SlidePageRoute(page: const LoginScreen()),
                      );
                    },
                    child: Text(
                      'already_have_account'.tr(),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
  }
}