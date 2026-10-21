import '../db/report_repository.dart';
import '../models/project.dart';
import '../models/project_bundle.dart';
import 'cloud_service.dart';

/// 依登入者可看的專案,從雲端下載專案包並建立/更新本機專案。
/// 員工不建專案:專案基本資料與要徑都來自工程管理的推播。
class ProjectSyncResult {
  final MeResult me;

  /// 本機專案(只含登入者可看的)。
  final List<Project> projects;

  /// 每個專案下載專案包的錯誤(專案顯示名稱 → 原因)。
  final Map<int, String> bundleErrors;

  const ProjectSyncResult({
    required this.me,
    required this.projects,
    required this.bundleErrors,
  });
}

class ProjectSync {
  ProjectSync({CloudService? cloud, ReportRepository? repo})
    : _cloud = cloud ?? CloudService.instance,
      _repo = repo ?? ReportRepository.instance;

  final CloudService _cloud;
  final ReportRepository _repo;

  static const defaultCompany = '振愷營造';

  /// 工程管理專案包 → 本機專案資料。沒給的欄位用合理預設
  /// (完工日沒給就用開工日,「剩餘天數」會顯示 0)。
  static Project projectFromBundle(ProjectBundle b) {
    final start = b.plannedStart ?? DateTime.now();
    return Project(
      name: b.displayName,
      companyName: b.company.isNotEmpty ? b.company : defaultCompany,
      startDate: start,
      plannedCompletionDate: b.plannedEnd ?? start,
      basementFloors: b.basementFloors,
      aboveGroundFloors: b.aboveGroundFloors,
      roofFloors: b.roofFloors,
      platformProjectId: b.projectId,
    );
  }

  Future<ProjectSyncResult> sync({String? expectEmail}) async {
    final me = await _cloud.fetchMe(expectEmail: expectEmail);
    final errors = <int, String>{};
    final projects = <Project>[];
    for (final mp in me.me?.projects ?? const <MeProject>[]) {
      final result = await _cloud.fetchBundle(mp.projectId);
      final bundle = result.bundle;
      if (result.error != null) errors[mp.projectId] = result.error!;
      if (bundle == null) continue;
      projects.add(await _repo.upsertCloudProject(projectFromBundle(bundle)));
    }
    return ProjectSyncResult(me: me, projects: projects, bundleErrors: errors);
  }
}
