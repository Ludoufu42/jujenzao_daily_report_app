import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jujenzao_daily_report_app/models/inspection_checklist.dart';
import 'package:jujenzao_daily_report_app/models/project_bundle.dart';
import 'package:jujenzao_daily_report_app/models/work_sequence.dart';
import 'package:jujenzao_daily_report_app/services/auth_user.dart';
import 'package:jujenzao_daily_report_app/services/cloud_service.dart';
import 'package:jujenzao_daily_report_app/services/project_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _bundle = {
  'schema': 'project-bundle/1',
  'ver': 3,
  'pushed_at': '2026-10-20 18:05',
  'project': {
    'project_id': 2,
    'short': '白平衡II館',
    'name': '白平衡II館新建工程',
    'basement_floors': 0,
    'above_ground_floors': 2,
    'roof_floors': 1,
    'planned_start': '2026-11-02',
  },
  // 故意亂序:解析後要依 seq 排。
  'items': [
    {'seq': 2, 'code': 'T201', 'name': '地上一樓 放樣工程', 'grp': '地上一樓', 'path': '主要徑'},
    {'seq': 1, 'code': 'T102', 'name': '假設工程 圍籬施作', 'grp': '假設工程', 'path': '主要徑'},
    {'seq': 3, 'code': 'T202', 'name': '地上一樓 柱鋼筋組立', 'grp': '地上一樓', 'path': '主要徑'},
  ],
};

String _fakeJwt({String email = 'Worker@Gmail.com', int? exp}) {
  String enc(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  final e = exp ?? DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
  return '${enc({'alg': 'RS256'})}.${enc({'email': email, 'name': '王小明', 'exp': e})}.sig';
}

void main() {
  group('WorkSequence / ProjectBundle', () {
    final bundle = ProjectBundle.fromJson(_bundle);
    final seq = bundle.sequence;

    test('依 seq 排序、用代號找工項與下一項', () {
      expect(seq.ver, 3);
      expect(seq.items.map((i) => i.code), ['T102', 'T201', 'T202']);
      expect(seq.byCode('T201')!.name, '地上一樓 放樣工程');
      expect(seq.next('T102')!.code, 'T201');
      expect(seq.next('T202'), isNull);
      expect(seq.next('不存在'), isNull);
      expect(seq.next(null), isNull);
    });

    test('今日要徑只能是昨天的要徑或它後面的,絕不是更早的', () {
      expect(seq.itemsFrom('T201').map((i) => i.code), ['T201', 'T202']); // 跟昨天同一項、或往後
      expect(seq.itemsFrom('T202').map((i) => i.code), ['T202']); // 昨天已在最後一項
      expect(seq.itemsFrom('T102').length, 3);
      expect(seq.itemsFrom(null).length, 3); // 第一份日報:全部可選
      expect(seq.itemsFrom('不存在').length, 3);
      expect(seq.itemsFrom('T201').any((i) => i.code == 'T102'), isFalse);
    });

    test('改名不影響識別:只認代號', () {
      final renamed = WorkSequence(
        projectId: 2,
        projectShort: '',
        ver: 4,
        pushedAt: '',
        items: const [WorkItem(seq: 1, code: 'T102', name: '全新名稱')],
      );
      expect(renamed.byCode('T102')!.name, '全新名稱');
      expect(renamed.byCode('假設工程 圍籬施作'), isNull);
    });

    test('專案基本資料與層數', () {
      expect(bundle.projectId, 2);
      expect(bundle.displayName, '白平衡II館');
      expect([bundle.basementFloors, bundle.aboveGroundFloors, bundle.roofFloors], [0, 2, 1]);
      expect(bundle.plannedStart, DateTime(2026, 11, 2));
      expect(bundle.plannedEnd, isNull);
    });

    test('專案包轉成本機專案:沒給的欄位用預設', () {
      final p = ProjectSync.projectFromBundle(bundle);
      expect(p.name, '白平衡II館');
      expect(p.companyName, ProjectSync.defaultCompany);
      expect(p.platformProjectId, 2);
      expect(p.startDate, DateTime(2026, 11, 2));
      expect(p.plannedCompletionDate, DateTime(2026, 11, 2));
      expect(p.aboveGroundFloors, 2);
    });

    test('格式不對會丟例外', () {
      expect(
        () => ProjectBundle.fromJson({..._bundle, 'schema': 'other/1'}),
        throwsFormatException,
      );
    });

    test('查驗表用名稱含有的關鍵字找', () {
      expect(templateForWorkItem('地上一樓 柱鋼筋組立'), isNotNull);
      expect(templateForWorkItem('假設工程 圍籬施作'), isNull);
    });
  });

  group('AuthUser', () {
    test('解開 ID token:email 轉小寫、取到期時間', () {
      final u = AuthUser.fromIdToken(_fakeJwt())!;
      expect(u.email, 'worker@gmail.com');
      expect(u.name, '王小明');
      expect(u.isFresh, isTrue);
    });

    test('快過期或已過期不算有效;壞 token 回 null', () {
      final soon = DateTime.now().add(const Duration(seconds: 30)).millisecondsSinceEpoch ~/ 1000;
      expect(AuthUser.fromIdToken(_fakeJwt(exp: soon))!.isFresh, isFalse);
      expect(AuthUser.fromIdToken('a.b'), isNull);
      expect(AuthUser.fromIdToken('x.y.z'), isNull);
    });
  });

  group('CloudService', () {
    final cloud = CloudService.instance;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      cloud.tokenProvider = () async => 'tok';
    });

    test('沒有登入 token:不連線,回報登入問題', () async {
      cloud.tokenProvider = () async => null;
      cloud.client = MockClient((req) async => fail('不該連線'));
      final r = await cloud.fetchMe();
      expect(r.me, isNull);
      expect(r.error!.isAuthProblem, isTrue);
    });

    test('帶 Bearer token;下載專案包後存快取,離線仍可用', () async {
      var online = true;
      cloud.client = MockClient((req) async {
        if (!online) throw http.ClientException('offline');
        expect(req.headers['Authorization'], 'Bearer tok');
        expect(req.url.path, '/app/projects/2/bundle');
        return http.Response.bytes(utf8.encode(jsonEncode(_bundle)), 200);
      });
      final first = await cloud.fetchBundle(2);
      expect(first.bundle!.ver, 3);
      expect(first.fromCache, isFalse);

      online = false;
      final second = await cloud.fetchBundle(2);
      expect(second.bundle!.ver, 3);
      expect(second.fromCache, isTrue);
      expect(second.error, isNotNull);
    });

    test('下載專案包 404:說明還沒推播;沒快取就沒有專案包', () async {
      cloud.client = MockClient((req) async => http.Response('nf', 404));
      final r = await cloud.fetchBundle(9);
      expect(r.bundle, isNull);
      expect(r.error, contains('推播'));
    });

    test('/me 取得專案清單;403 不用快取、要讓使用者知道', () async {
      cloud.client = MockClient((req) async => http.Response.bytes(
        utf8.encode(jsonEncode({
          'email': 'worker@gmail.com',
          'name': '王小明',
          'projects': [
            {'project_id': 2, 'short': '白平衡II館', 'name': 'x', 'bundle_ver': 3},
          ],
        })),
        200,
      ));
      final ok = await cloud.fetchMe();
      expect(ok.me!.projects.single.projectId, 2);

      cloud.client = MockClient((req) async => http.Response('no', 403));
      final denied = await cloud.fetchMe();
      expect(denied.me, isNull);
      expect(denied.error!.isForbidden, isTrue);
    });

    test('離線時 /me 用快取,但只用同一個 email 的', () async {
      cloud.client = MockClient((req) async => http.Response.bytes(
        utf8.encode(jsonEncode({'email': 'worker@gmail.com', 'name': 'x', 'projects': []})),
        200,
      ));
      await cloud.fetchMe();
      cloud.client = MockClient((req) async => throw http.ClientException('offline'));
      final same = await cloud.fetchMe(expectEmail: 'Worker@gmail.com');
      expect(same.fromCache, isTrue);
      final other = await cloud.fetchMe(expectEmail: 'someone-else@gmail.com');
      expect(other.me, isNull);
    });

    test('上傳日報:送到對的網址,回傳修訂號;401 要重新登入', () async {
      cloud.client = MockClient((req) async {
        expect(req.method, 'PUT');
        expect(req.url.path, '/app/projects/2/reports/2026-10-21');
        expect(req.headers['Authorization'], 'Bearer tok');
        expect(jsonDecode(req.body)['today_work']['code'], 'T102');
        return http.Response(jsonEncode({'ok': true, 'rev': 2}), 200);
      });
      final rev = await cloud.uploadReport(2, '2026-10-21', {
        'today_work': {'code': 'T102', 'ver': 3},
      });
      expect(rev, 2);

      cloud.client = MockClient((req) async => http.Response('x', 401));
      expect(
        () => cloud.uploadReport(2, '2026-10-21', {}),
        throwsA(isA<CloudException>().having((e) => e.isAuthProblem, 'auth', true)),
      );
    });

    test('登出清掉快取', () async {
      cloud.client = MockClient((req) async => http.Response.bytes(utf8.encode(jsonEncode(_bundle)), 200));
      await cloud.fetchBundle(2);
      expect(await cloud.readCachedBundle(2), isNotNull);
      await cloud.clearCache();
      expect(await cloud.readCachedBundle(2), isNull);
    });
  });
}
