import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/canvass_service.dart';

class Bank {
  const Bank({required this.name, required this.code});

  final String name;
  final String code;
}

/// The signed-in person's own record in erims, from the my-account function.
class AccountDetails {
  const AccountDetails({
    required this.role,
    required this.firstName,
    required this.lastName,
    required this.phone,
    this.whatsappNumber,
    this.email,
    this.bankName,
    this.bankCode,
    this.accountNumber,
    this.accountName,
  });

  final String role;
  final String firstName;
  final String lastName;
  final String phone;
  final String? whatsappNumber;
  final String? email;
  final String? bankName;
  final String? bankCode;
  final String? accountNumber;
  final String? accountName;

  bool get hasBank => accountNumber != null;

  factory AccountDetails.fromJson(Map<String, dynamic> j) => AccountDetails(
        role: j['role'] as String,
        firstName: j['first_name'] as String,
        lastName: j['last_name'] as String,
        phone: j['phone'] as String,
        whatsappNumber: j['whatsapp_number'] as String?,
        email: j['email'] as String?,
        bankName: j['bank_name'] as String?,
        bankCode: j['bank_code'] as String?,
        accountNumber: j['account_number'] as String?,
        accountName: j['account_name'] as String?,
      );
}

/// Account details and bank lookups go through erims's edge functions, which
/// hold the Paystack key and check each account with the bank. Online only.
class AccountApi {
  AccountApi(this._client);

  final SupabaseClient _client;

  /// The bank list rarely changes; once a session is enough.
  static List<Bank>? _banks;

  Future<AccountDetails> get() async => AccountDetails.fromJson(await _call('my-account', {'action': 'get'}));

  /// Saves only what's given; erims verifies [bank] with the bank and stores
  /// the name on the account. [clear] lists fields to empty.
  Future<AccountDetails> update({
    String? whatsappNumber,
    String? email,
    Set<String> clear = const {},
    ({String bankCode, String accountNumber})? bank,
  }) async =>
      AccountDetails.fromJson(await _call('my-account', {
        'action': 'update',
        if (whatsappNumber != null || clear.contains('whatsapp_number')) 'whatsapp_number': whatsappNumber,
        if (email != null || clear.contains('email')) 'email': email,
        if (bank != null) 'bank': {'bank_code': bank.bankCode, 'account_number': bank.accountNumber},
      }));

  Future<List<Bank>> banks() async {
    if (_banks != null) return _banks!;
    final res = await _call('bank-accounts', {'action': 'banks'});
    return _banks = [
      for (final b in res['banks'] as List) Bank(name: b['name'] as String, code: b['code'] as String),
    ];
  }

  /// The name on an account, to show before saving.
  Future<String> resolve(String bankCode, String accountNumber) async {
    final res = await _call('bank-accounts', {
      'action': 'resolve',
      'bank_code': bankCode,
      'account_number': accountNumber,
    });
    return res['account_name'] as String;
  }

  Future<Map<String, dynamic>> _call(String fn, Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke(fn, body: body);
      return res.data as Map<String, dynamic>;
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map && details['error'] is String ? details['error'] as String : null;
      throw CanvassException(message ?? 'Something went wrong (${e.status}). Please try again.');
    } catch (e) {
      throw CanvassException(CanvassService.describeError(e));
    }
  }
}
