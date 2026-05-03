class Validators {
  Validators._();

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required';
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value.trim())) return 'Enter a valid email';
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'At least 8 characters required';
    return null;
  }

  static String? username(String? value) {
    if (value == null || value.trim().isEmpty) return 'Username is required';
    final trimmed = value.trim();
    if (trimmed.length < 3) return 'Username must be at least 3 characters';
    if (trimmed.length > 30) return 'Username must be 30 characters or less';
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(trimmed)) {
      return 'Username can only contain letters, numbers, and underscores';
    }
    return null;
  }

  static String? required(String? value, {String fieldName = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$fieldName is required';
    return null;
  }

  static String? confirmPassword(String? value, {required String matchAgainst}) {
    if (value == null || value.isEmpty) return 'Please confirm your password';
    if (value != matchAgainst) return 'Passwords do not match';
    return null;
  }

  static String? sessionTitle(String? value) {
    if (value == null || value.trim().isEmpty) return 'Title is required';
    if (value.trim().length > 100) return 'Title must be 100 characters or less';
    return null;
  }

  static String? sessionDescription(String? value) {
    if (value == null) return null;
    if (value.length > 50) return 'Description must be 50 characters or less';
    return null;
  }

  static String? bio(String? value) {
    if (value == null) return null;
    if (value.length > 150) return 'Bio must be 150 characters or less';
    return null;
  }
}