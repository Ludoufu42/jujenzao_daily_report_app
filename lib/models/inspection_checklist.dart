/// One row of a checklist template — the item name and what to actually
/// check for it. The pass/fail result itself is recorded per-inspection,
/// not part of the template.
class ChecklistItemDef {
  final String name;
  final String description;
  const ChecklistItemDef(this.name, this.description);
}

class InspectionChecklistTemplate {
  final String templateName;
  final List<ChecklistItemDef> items;
  const InspectionChecklistTemplate({
    required this.templateName,
    required this.items,
  });
}

const _layoutTemplate = InspectionChecklistTemplate(
  templateName: '放樣工程',
  items: [
    ChecklistItemDef('1. 構件尺寸核對', '核對結構圖之梁柱尺寸。'),
    ChecklistItemDef('2. 開口尺寸核對', '確認各門窗之MO開口、台度尺寸。'),
    ChecklistItemDef('3. 樓梯踏樹核對', '檢視該層樓梯踏數、級高級深是否合乎圖說，檢討是否有淨高不足(<190)。'),
    ChecklistItemDef('4. 柱預留筋檢查', '柱預留筋是否有保護層不足，如<3cm應通知主管是否擴柱。'),
    ChecklistItemDef('5. 牆預留筋及管路檢查', '是否有出線情況，應通知包商修改?'),
    ChecklistItemDef('6. 梁下淨高核對', '核算結構圖，梁下淨高是否有正確標示'),
  ],
);

const _columnWallRebarTemplate = InspectionChecklistTemplate(
  templateName: '柱牆鋼筋組立',
  items: [
    ChecklistItemDef('1. 鋼筋規格', '核對主筋與箍筋號數、數量正確。尤其要確認箍筋是否為420W?'),
    ChecklistItemDef('2. 續接範圍', '續接器高度是否靠近緊密維束區，如有下層料單應調整。'),
    ChecklistItemDef('3. 扭力測試', '柱續接器扭力值是否有達到規範值。'),
    ChecklistItemDef('4. 主筋緊貼', '主筋是否有緊貼箍筋。'),
    ChecklistItemDef('5. 輔助繫筋', '輔助繫筋是否有緊貼主筋'),
    ChecklistItemDef('6. 保護層', '造型柱如有埋保麗龍，務必要有5公分之保護層，不得緊貼鋼筋。'),
    ChecklistItemDef('7. 柱內埋管', '柱內埋管含配件之投影面積是否合乎規範。(4%/45x45以下禁止埋管)'),
    ChecklistItemDef('8. 垂直定位', '柱鋼筋整體垂直無歪斜偏位。'),
  ],
);

const _interiorWallFormworkTemplate = InspectionChecklistTemplate(
  templateName: '內牆封模',
  items: [
    ChecklistItemDef('1. 垃圾清理', '模內木屑、鐵絲、雜物確實清除。'),
    ChecklistItemDef('2. 封底洗孔', '柱牆底部留洗孔以利沖洗排污。'),
    ChecklistItemDef('4. 鋼筋與水電', '鋼筋綁紮與水電管線施作完畢。'),
    ChecklistItemDef('5. 墊塊保護層', '鋼筋保護層墊塊緊貼無位移。'),
    ChecklistItemDef('6. 螺桿與支撐', '模板緊結螺桿與斜撐牢固到位。'),
    ChecklistItemDef('7. 縫隙密合', '模板接縫嚴密，防灌漿時漏漿。'),
    ChecklistItemDef('8. 預留孔尺寸', '門窗框、管路預留壓艙位置正確。'),
    ChecklistItemDef('9. 垂直度複查', '用鉛錘或儀器複測模板垂直度。'),
  ],
);

const _beamSlabRebarTemplate = InspectionChecklistTemplate(
  templateName: '梁板鋼筋組立',
  items: [
    ChecklistItemDef('1. 鋼筋規格', '梁主筋與板筋號數、間距符圖說。'),
    ChecklistItemDef('2. 梁錨錠長', '梁主筋入柱錨錠與彎鉤長度足夠。'),
    ChecklistItemDef('3. 搭接錯開', '梁上鐵下鐵搭接位置依規範錯開。'),
    ChecklistItemDef('4. 肋筋加密', '梁端圍束區肋筋間距確實加密。'),
    ChecklistItemDef('5. 梁柱接頭', '梁柱交接處內部核心箍筋未漏綁。'),
    ChecklistItemDef('6. 開口補強', '板與梁預留孔洞四周依圖設補強筋。'),
    ChecklistItemDef('7. 雙層板筋', '板上下層筋以馬椅支撐固定高度。'),
    ChecklistItemDef('8. 保護層厚', '梁底、梁側及板底墊塊數量充足。'),
    ChecklistItemDef('9. 清潔無油', '鋼筋表面無水泥渣、油污與浮鏽。'),
    ChecklistItemDef('10. 綁紮牢固', '鋼筋交叉點紮絲確實扭緊無鬆脫。'),
  ],
);

const _floorPourTemplate = InspectionChecklistTemplate(
  templateName: '樓層灌漿',
  items: [
    ChecklistItemDef('1. 坍度試驗', '現場取樣做坍度與氯離子檢測。'),
    ChecklistItemDef('2. 濕潤潤管', '壓送車管路先以水泥砂漿潤滑。'),
    ChecklistItemDef('3. 動線照明', '灌漿動線順暢且夜間照明充足。'),
    ChecklistItemDef('4. 天氣確認', '確認氣象預報，大雨天停止灌漿。'),
    ChecklistItemDef('5. 搗實機具', '準備足夠且功能正常的振動機。'),
    ChecklistItemDef('6. 震動搗實', '確實搗實，避免蜂巢與內部空洞。'),
    ChecklistItemDef('7. 表面整體', '依設計高程進行耙平與光面壓實。'),
    ChecklistItemDef('8. 試體取樣', '依規範現場製作抗壓強度試體。'),
    ChecklistItemDef('9. 灑水養護', '凝結後即時灑水並覆蓋防曬養護。'),
    ChecklistItemDef('10. 拆模時間', '依規範達到強度與天數方可拆模。'),
  ],
);

/// Maps a 要徑 step's second-half work-item name (see critical_path.dart) to
/// its inspection checklist template. 柱鋼筋組立 and 牆鋼筋組立 share the same
/// 柱牆鋼筋組立 template (only one was provided for both). 外模組立, and the
/// fixed 假設工程/基礎工程 items, have no template yet — no inspection is
/// required for those until templates are defined for them too.
const Map<String, InspectionChecklistTemplate> kInspectionTemplatesBySecondHalf = {
  '放樣工程': _layoutTemplate,
  '柱鋼筋組立': _columnWallRebarTemplate,
  '牆鋼筋組立': _columnWallRebarTemplate,
  '內牆封模': _interiorWallFormworkTemplate,
  '梁板鋼筋組立': _beamSlabRebarTemplate,
  '樓層灌漿': _floorPourTemplate,
};

/// Looks up the checklist template for a 要徑 work item by its name from the
/// 工程管理 delivery package (e.g. "地上二樓 放樣工程" or "外模組立"): the
/// template whose key appears in the name. Returns null when that item has
/// no defined checklist (inspection not required). The item itself is always
/// identified by its fixed code — the name is only used to pick a checklist.
InspectionChecklistTemplate? templateForWorkItem(String itemName) {
  for (final entry in kInspectionTemplatesBySecondHalf.entries) {
    if (itemName.contains(entry.key)) return entry.value;
  }
  return null;
}
