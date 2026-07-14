enum TradeCategoryType { labor, material, equipment }

class TradeCategoryDef {
  final String name;
  final TradeCategoryType type;
  final List<(String name, String unit)> presetItems;

  const TradeCategoryDef({
    required this.name,
    required this.type,
    required this.presetItems,
  });
}

const List<TradeCategoryDef> kTradeCategories = [
  TradeCategoryDef(
    name: '假設工程',
    type: TradeCategoryType.labor,
    presetItems: [
      ('臨時工', '工'),
      ('施工架', '工'),
      ('安全圍籬', '工'),
      ('點井工程', '工'),
      ('吊料工程', '工'),
    ],
  ),
  TradeCategoryDef(
    name: '基礎工程',
    type: TradeCategoryType.labor,
    presetItems: [
      ('土方工程', '工'),
      ('機械擋土柱工程', '工'),
      ('人工擋土柱工程', '工'),
      ('鋼軌樁工程', '工'),
      ('預壘樁工程', '工'),
      ('安全支撐工程', '工'),
      ('安全監測工程', '工'),
    ],
  ),
  TradeCategoryDef(
    name: '結構工程',
    type: TradeCategoryType.labor,
    presetItems: [
      ('鋼筋工程', '工'),
      ('模板工程', '工'),
      ('鋼構工程', '工'),
      ('混凝土壓送工程', '工'),
      ('整體粉光工程', '工'),
      ('放樣工程', '工'),
    ],
  ),
  TradeCategoryDef(
    name: '機電工程',
    type: TradeCategoryType.labor,
    presetItems: [
      ('水電工程', '工'),
      ('消防工程', '工'),
      ('弱電工程', '工'),
      ('電梯工程', '工'),
      ('汙水工程', '工'),
      ('空調工程', '工'),
      ('機械車位工程', '工'),
    ],
  ),
  TradeCategoryDef(
    name: '裝修工程',
    type: TradeCategoryType.labor,
    presetItems: [
      ('外牆吊線', '工'),
      ('外牆打底', '工'),
      ('外牆貼磚', '工'),
      ('外牆仿石漆', '工'),
      ('外牆石材', '工'),
      ('輕隔間工程', '工'),
      ('內牆打底', '工'),
      ('內牆貼磚', '工'),
      ('地坪打底', '工'),
      ('地坪貼磚', '工'),
      ('樓梯貼磚', '工'),
      ('鋁門窗工程', '工'),
      ('金屬門工程', '工'),
      ('不鏽鋼鐵件工程', '工'),
      ('鋁格柵及欄杆工程', '工'),
      ('防水工程', '工'),
      ('玻璃工程', '工'),
      ('油漆工程', '工'),
    ],
  ),
  TradeCategoryDef(
    name: '營建材料',
    type: TradeCategoryType.material,
    presetItems: [
      ('280鋼筋', 'T'),
      ('420W鋼筋', 'T'),
      ('2000psi混凝土', 'm3'),
      ('3000psi混凝土', 'm3'),
      ('3500psi混凝土', 'm3'),
      ('4000psi混凝土', 'm3'),
      ('5000psi混凝土', 'm3'),
      ('低強度混凝土', 'm3'),
      ('紅磚', '塊'),
      ('水泥', '包'),
      ('沙', 'm3'),
      ('碎石', 'm3'),
      ('益膠泥(貴)', '包'),
      ('益膠泥(便宜)', '包'),
      ('填縫劑(粗)', '包'),
      ('填縫劑(細)', '包'),
      ('二丁掛(色1)', '塊'),
      ('營建廢棄物清運', 'm3'),
      ('混合廢棄物清運', 'm3'),
    ],
  ),
  TradeCategoryDef(
    name: '機具設備',
    type: TradeCategoryType.equipment,
    presetItems: [
      ('怪手PC30', 'hr'),
      ('怪手PC60', 'hr'),
      ('怪手PC120', 'hr'),
      ('怪手PC200', 'hr'),
      ('怪手PC300', 'hr'),
      ('破碎機', '天'),
      ('板車', '趟'),
      ('吊卡', 'hr'),
      ('全吊25T', '趟'),
      ('全吊40T', '趟'),
      ('全吊60T', '趟'),
      ('拖車35T', '趟'),
      ('卡車8.8T', '趟'),
      ('卡車21T', '趟'),
    ],
  ),
];
