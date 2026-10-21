import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/project_bundle.dart';
import 'cloud_config.dart';
import 'google_auth.dart';

class CloudException implements Exception {
  final String message;

  /// HTTP 狀態碼;沒連上雲端或沒登入時是 null。
  final int? statusCode;
  CloudException(this.message, {this.statusCode});

  /// 登入無效或已過期(要重新登入)。
  bool get isAuthProblem => statusCode == 401;

  /// 已登入,但不在名單、或沒有這個專案的權限。
  bool get isForbidden => statusCode == 403;

  @override
  String toString() => message;
}

class BundleResult {
  final ProjectBundle? bundle;
  final bool fromCache;
  final String? error;
  const BundleResult(this.bundle, {this.fromCache = false, this.error});
}

class MeResult {
  final MeInfo? me;
  final bool fromCache;
  final CloudException? error;
  const MeResult(this.me, {this.fromCache = false, this.error});
}

/// 跟 Cloudflare Worker 溝通。員工用 Google 登入,每次請求帶 ID token,
/// Worker 驗證登入並依名單決定能看哪些專案。
class CloudService {
  CloudService._internal();
  static final CloudService instance = CloudService._internal();

  /// 測試可換成假的 http client / 假的 token。
  http.Client client = http.Client();
  Future<String?> Function() tokenProvider = () =>
      GoogleAuth.instance.getIdToken();

  static const _timeout = Duration(seconds: 20);

  Uri _uri(String path) =>
      Uri.parse('${CloudConfig.workerUrl.replaceAll(RegExp(r'/+$'), '')}$path');

  Future<Map<String, String>> _authHeaders() async {
    final token = await tokenProvider();
    if (token == null) {
      throw CloudException('尚未登入,或登入已過期,請重新登入', statusCode: 401);
    }
    return {'Authorization': 'Bearer $token'};
  }

  CloudException _httpError(http.Response res) {
    final code = res.statusCode;
    final msg = switch (code) {
      401 => '登入無效或已過期,請重新登入',
      403 => '你的帳號沒有權限(不在名單內,或沒有這個專案)',
      404 => '雲端還沒有這份資料',
      _ => '雲端回應 $code',
    };
    return CloudException(msg, statusCode: code);
  }

  Future<http.Response> _get(String path) async {
    final res = await client
        .get(_uri(path), headers: await _authHeaders())
        .timeout(_timeout);
    if (res.statusCode != 200) throw _httpError(res);
    return res;
  }

  // ---------------- 本機快取(離線時用上次的) ----------------

  static const _meKey = 'cloud_me';
  static String _bundleKey(int pid) => 'project_bundle_$pid';

  Future<void> _writeCache(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (_) {
      // 快取寫不進去不影響使用。
    }
  }

  Future<String?> _readCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (_) {
      return null;
    }
  }

  /// 清掉本機快取(登出時用,避免下一位登入者看到上一位的專案)。
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys().toList()) {
        if (k == _meKey || k.startsWith('project_bundle_')) {
          await prefs.remove(k);
        }
      }
    } catch (_) {}
  }

  // ---------------- 登入者與專案 ----------------

  /// 登入者與可看的專案。沒網路時回傳上次的快取(同一個 email 才採用);
  /// 但 401/403(帳號有問題)不用快取,必須讓使用者知道。
  Future<MeResult> fetchMe({String? expectEmail}) async {
    CloudException? error;
    try {
      final res = await _get('/app/me');
      final body = utf8.decode(res.bodyBytes);
      final me = MeInfo.fromJson(jsonDecode(body) as Map<String, dynamic>);
      await _writeCache(_meKey, body);
      return MeResult(me);
    } on CloudException catch (e) {
      if (e.isAuthProblem || e.isForbidden) return MeResult(null, error: e);
      error = e;
    } catch (e) {
      error = CloudException('連不到雲端($e)');
    }
    final raw = await _readCache(_meKey);
    if (raw != null) {
      try {
        final me = MeInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (expectEmail == null || me.email == expectEmail.toLowerCase()) {
          return MeResult(me, fromCache: true, error: error);
        }
      } catch (_) {}
    }
    return MeResult(null, error: error);
  }

  /// 下載專案最新的專案包(基本資料 + 要徑順序),成功就存快取;
  /// 失敗(沒網路、工程管理還沒推播)回傳上次的快取。
  Future<BundleResult> fetchBundle(int projectId) async {
    String? error;
    try {
      final res = await _get('/app/projects/$projectId/bundle');
      final body = utf8.decode(res.bodyBytes);
      final bundle = ProjectBundle.fromJson(
        jsonDecode(body) as Map<String, dynamic>,
      );
      await _writeCache(_bundleKey(projectId), body);
      return BundleResult(bundle);
    } on CloudException catch (e) {
      error = e.statusCode == 404 ? '工程管理還沒推播這個專案' : e.message;
    } catch (e) {
      error = '連不到雲端($e)';
    }
    final cached = await readCachedBundle(projectId);
    return BundleResult(cached, fromCache: cached != null, error: error);
  }

  Future<ProjectBundle?> readCachedBundle(int projectId) async {
    final raw = await _readCache(_bundleKey(projectId));
    if (raw == null) return null;
    try {
      return ProjectBundle.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // ---------------- 日報 ----------------

  /// 早於 [date](YYYY-MM-DD)的最新一份日報;沒有就回傳 null。
  Future<Map<String, dynamic>?> fetchPreviousReport(
    int projectId,
    String date,
  ) async {
    try {
      final res = await _get('/app/projects/$projectId/reports?before=$date');
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on CloudException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// 上傳日報 PDF(含照片與簽名)。日報本身要先送出過,否則雲端回 409。
  Future<void> uploadReportPdf(
    int projectId,
    String date,
    List<int> pdfBytes,
  ) async {
    final res = await client
        .put(
          _uri('/app/projects/$projectId/reports/$date/pdf'),
          headers: {
            ...await _authHeaders(),
            'Content-Type': 'application/pdf',
          },
          body: pdfBytes,
        )
        .timeout(const Duration(seconds: 60));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw CloudException(
        res.statusCode == 409 ? '雲端還沒有這天的日報,請先儲存日報' : _httpError(res).message,
        statusCode: res.statusCode,
      );
    }
  }

  /// 當天雲端上最新的一份日報(`daily-report/2`);雲端還沒有就回傳 null。
  Future<Map<String, dynamic>?> fetchReport(int projectId, String date) async {
    try {
      final res = await _get('/app/projects/$projectId/reports/$date');
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on CloudException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// 送出日報;填表人、時間、修訂號由 Worker 決定。回傳這次的修訂號。
  Future<int> uploadReport(
    int projectId,
    String date,
    Map<String, Object?> report,
  ) async {
    final res = await client
        .put(
          _uri('/app/projects/$projectId/reports/$date'),
          headers: {
            ...await _authHeaders(),
            'Content-Type': 'application/json',
          },
          body: utf8.encode(jsonEncode(report)),
        )
        .timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) throw _httpError(res);
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return (j['rev'] as num?)?.toInt() ?? 0;
  }
}
