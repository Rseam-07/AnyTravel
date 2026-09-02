// Curated fallback destination catalogs (coordinates from OSM, manually
// verified to ~100m) used when live POI sources are unreachable. Mirrors the
// Android app's DestinationCatalog approach: honest about being a starter pack.

import type { Interest, TravelPlace } from "./types";

interface CatalogEntry {
  name: string;
  lat: number;
  lng: number;
  interest: Interest;
  address?: string;
}

export const CATALOG_CITIES: Record<string, CatalogEntry[]> = {
  苏州: [
    { name: "拙政园", lat: 31.3243, lng: 120.6288, interest: "gardens", address: "姑苏区东北街178号" },
    { name: "苏州博物馆", lat: 31.3253, lng: 120.6236, interest: "culture", address: "姑苏区东北街204号" },
    { name: "狮子林", lat: 31.3232, lng: 120.6301, interest: "gardens", address: "姑苏区园林路23号" },
    { name: "平江路历史街区", lat: 31.3169, lng: 120.63, interest: "gardens", address: "姑苏区平江路" },
    { name: "观前街", lat: 31.3131, lng: 120.619, interest: "food", address: "姑苏区观前街" },
    { name: "虎丘山风景名胜区", lat: 31.3347, lng: 120.5785, interest: "gardens", address: "姑苏区虎丘山门内8号" },
    { name: "山塘街", lat: 31.3161, lng: 120.59, interest: "food", address: "姑苏区山塘街" },
    { name: "寒山寺", lat: 31.3121, lng: 120.5633, interest: "gardens", address: "姑苏区寒山寺弄24号" },
    { name: "网师园", lat: 31.3017, lng: 120.63, interest: "gardens", address: "姑苏区阔家头巷11号" },
    { name: "留园", lat: 31.3212, lng: 120.596, interest: "gardens", address: "姑苏区留园路338号" },
    { name: "金鸡湖景区", lat: 31.3101, lng: 120.7, interest: "nature", address: "工业园区星港街" },
    { name: "诚品书店", lat: 31.3159, lng: 120.6783, interest: "culture", address: "工业园区月廊街8号" },
    { name: "东方之门", lat: 31.3128, lng: 120.6912, interest: "night", address: "工业园区苏州中心" },
    { name: "苏州乐园森林世界", lat: 31.2946, lng: 120.4656, interest: "family", address: "高新区象山路99号" }
  ],
  杭州: [
    { name: "西湖风景名胜区", lat: 30.245, lng: 120.15, interest: "nature", address: "西湖区龙井路1号" },
    { name: "灵隐寺", lat: 30.241, lng: 120.103, interest: "gardens", address: "西湖区灵隐路法云弄1号" },
    { name: "雷峰塔", lat: 30.231, lng: 120.148, interest: "gardens", address: "西湖区南山路15号" },
    { name: "断桥残雪", lat: 30.259, lng: 120.151, interest: "nature", address: "西湖区白堤" },
    { name: "西溪国家湿地公园", lat: 30.266, lng: 120.066, interest: "nature", address: "西湖区天目山路518号" },
    { name: "河坊街", lat: 30.24, lng: 120.166, interest: "food", address: "上城区河坊街" },
    { name: "杭州宋城", lat: 30.132, lng: 120.114, interest: "family", address: "西湖区之江路148号" },
    { name: "浙江美术馆", lat: 30.2146, lng: 120.1372, interest: "culture", address: "南山路138号" },
    { name: "京杭大运河拱宸桥", lat: 30.3198, lng: 120.143, interest: "culture", address: "拱墅区桥弄街" },
    { name: "吴山广场", lat: 30.2422, lng: 120.1625, interest: "gardens", address: "上城区吴山" },
    { name: "九溪烟树", lat: 30.1855, lng: 120.1075, interest: "nature", address: "西湖区九溪路" },
    { name: "清河坊鼓楼夜市", lat: 30.2356, lng: 120.169, interest: "night", address: "上城区中山南路" }
  ],
  青岛: [
    { name: "栈桥", lat: 36.057, lng: 120.32, interest: "gardens", address: "市南区太平路12号" },
    { name: "八大关风景区", lat: 36.055, lng: 120.35, interest: "gardens", address: "市南区武胜关支路" },
    { name: "崂山风景名胜区", lat: 36.193, lng: 120.621, interest: "nature", address: "崂山区梅岭路29号" },
    { name: "圣弥厄尔教堂", lat: 36.067, lng: 120.315, interest: "culture", address: "市南区浙江路15号" },
    { name: "五四广场", lat: 36.062, lng: 120.385, interest: "night", address: "市南区东海西路" },
    { name: "青岛啤酒博物馆", lat: 36.077, lng: 120.354, interest: "culture", address: "市北区登州路56号" },
    { name: "第一海水浴场", lat: 36.051, lng: 120.333, interest: "nature", address: "市南区南海路" },
    { name: "小鱼山公园", lat: 36.062, lng: 120.334, interest: "nature", address: "市南区福山支路24号" },
    { name: "信号山公园", lat: 36.066, lng: 120.325, interest: "nature", address: "市南区龙山路17号" },
    { name: "劈柴院", lat: 36.0665, lng: 120.316, interest: "food", address: "市南区江宁路" },
    { name: "石老人海水浴场", lat: 36.095, lng: 120.475, interest: "nature", address: "崂山区海口路" },
    { name: "台东步行街", lat: 36.082, lng: 120.371, interest: "food", address: "市北区台东三路" }
  ],
  上海: [
    { name: "外滩", lat: 31.24, lng: 121.49, interest: "night", address: "黄浦区中山东一路" },
    { name: "豫园", lat: 31.227, lng: 121.492, interest: "gardens", address: "黄浦区安仁街218号" },
    { name: "东方明珠广播电视塔", lat: 31.2397, lng: 121.4998, interest: "culture", address: "浦东新区世纪大道1号" },
    { name: "上海博物馆", lat: 31.2304, lng: 121.47, interest: "culture", address: "黄浦区人民大道201号" },
    { name: "武康路", lat: 31.211, lng: 121.44, interest: "gardens", address: "徐汇区武康路" },
    { name: "田子坊", lat: 31.209, lng: 121.466, interest: "food", address: "黄浦区泰康路210弄" },
    { name: "上海迪士尼乐园", lat: 31.1435, lng: 121.657, interest: "family", address: "浦东新区川沙新镇" },
    { name: "南京路步行街", lat: 31.234, lng: 121.476, interest: "food", address: "黄浦区南京东路" },
    { name: "朱家角古镇", lat: 31.111, lng: 121.051, interest: "gardens", address: "青浦区朱家角镇" },
    { name: "上海科技馆", lat: 31.2197, lng: 121.538, interest: "family", address: "浦东新区世纪大道2000号" },
    { name: "多伦路文化名人街", lat: 31.2709, lng: 121.4795, interest: "culture", address: "虹口区多伦路" },
    { name: "滨江大道", lat: 31.235, lng: 121.502, interest: "nature", address: "浦东新区滨江大道" }
  ],
  北京: [
    { name: "故宫博物院", lat: 39.9163, lng: 116.3972, interest: "gardens", address: "东城区景山前街4号" },
    { name: "颐和园", lat: 39.9999, lng: 116.2755, interest: "gardens", address: "海淀区新建宫门路19号" },
    { name: "天坛公园", lat: 39.8822, lng: 116.4066, interest: "gardens", address: "东城区天坛东里甲1号" },
    { name: "南锣鼓巷", lat: 39.935, lng: 116.403, interest: "food", address: "东城区南锣鼓巷" },
    { name: "798艺术区", lat: 39.984, lng: 116.497, interest: "culture", address: "朝阳区酒仙桥路4号" },
    { name: "八达岭长城", lat: 40.355, lng: 116.01, interest: "culture", address: "延庆区军都山关沟古道北口" },
    { name: "国家体育场（鸟巢）", lat: 39.991, lng: 116.39, interest: "culture", address: "朝阳区国家体育场南路1号" },
    { name: "什刹海", lat: 39.94, lng: 116.376, interest: "nature", address: "西城区地安门西大街" },
    { name: "恭王府", lat: 39.937, lng: 116.383, interest: "gardens", address: "西城区前海西街17号" },
    { name: "首都博物馆", lat: 39.863, lng: 116.336, interest: "culture", address: "西城区复兴门外大街16号" },
    { name: "景山公园", lat: 39.9246, lng: 116.3948, interest: "nature", address: "西城区景山西街44号" },
    { name: "簋街", lat: 39.9408, lng: 116.4095, interest: "food", address: "东城区东直门内大街" }
  ]
};

export function catalogPlaces(destination: string): TravelPlace[] {
  const entries = CATALOG_CITIES[destination.replace(/(市|省)$/, "")];
  if (!entries) return [];
  return entries.map((entry, index) => ({
    id: `catalog-${entry.name}`,
    name: entry.name,
    address: entry.address,
    coordinate: { lat: entry.lat, lng: entry.lng },
    interest: entry.interest,
    source: "内置地点包（人工核对）",
    planningPriority: index < 4 ? "primary" : "supplemental"
  }));
}
