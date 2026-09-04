// Builds the unfinished mainland-China destination pack from open, attributable data.
//
// Sources:
// - Wikidata: nearby article-backed POIs and sitelink notability signals (CC0)
// - Audiala Places: curated guide links and an additional notability signal (CC BY 4.0)
// - 88250/city-geo: China city centres used for spatial joins (Mulan PSL v2)
//
// The result is a planning snapshot. It deliberately does not claim live ticket prices,
// availability, or opening status. Run with: npm run harvest:domestic

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const webRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const outputPath = join(webRoot, "src/knowledge/raw/region-domestic-completion.json");
const cacheRoot = process.env.ANYTRAVEL_HARVEST_CACHE || join(tmpdir(), "anytravel-domestic-harvest");
mkdirSync(cacheRoot, { recursive: true });

const sourceURLs = {
  osmCopyright: "https://www.openstreetmap.org/copyright",
  wikidata: "https://www.wikidata.org/",
  audiala: "https://github.com/audiala/open-data",
  cityGeo: "https://github.com/88250/city-geo",
  mctCatalogue: "https://sjfw.mct.gov.cn/site/dataservice/base",
  mct2024February: "https://app.www.gov.cn/govdata/gov/202402/11/512030/article.html",
  mct2024December: "https://zwgk.mct.gov.cn/zfxxgkml/zykf/202412/t20241227_957450.html"
};

const destinations = [
  ["上海", "上海", "华东", 40], ["南京", "江苏", "华东", 38], ["苏州", "江苏", "华东", 38],
  ["无锡", "江苏", "华东", 32], ["常州", "江苏", "华东", 30], ["镇江", "江苏", "华东", 30],
  ["扬州", "江苏", "华东", 34], ["南通", "江苏", "华东", 35], ["徐州", "江苏", "华东", 45],
  ["杭州", "浙江", "华东", 45], ["宁波", "浙江", "华东", 45], ["温州", "浙江", "华东", 48],
  ["绍兴", "浙江", "华东", 42], ["嘉兴", "浙江", "华东", 68], ["湖州", "浙江", "华东", 65],
  ["金华", "浙江", "华东", 90], ["台州", "浙江", "华东", 55], ["衢州", "浙江", "华东", 50],
  ["舟山", "浙江", "华东", 75], ["淄博", "山东", "华东", 48], ["潍坊", "山东", "华东", 55],
  ["泰安", "山东", "华东", 55], ["临沂", "山东", "华东", 95],
  ["重庆", "重庆", "西南", 65], ["成都", "四川", "西南", 55], ["乐山", "四川", "西南", 60],
  ["绵阳", "四川", "西南", 55], ["阿坝", "四川", "西南", 170], ["九寨沟", "四川", "西南", 85],
  ["昆明", "云南", "西南", 60], ["大理", "云南", "西南", 85], ["丽江", "云南", "西南", 75],
  ["香格里拉", "云南", "西南", 100], ["西双版纳", "云南", "西南", 110],
  ["贵阳", "贵州", "西南", 55], ["遵义", "贵州", "西南", 65], ["凯里", "贵州", "西南", 80],
  ["拉萨", "西藏", "西南", 110],
  ["西安", "陕西", "西北", 60], ["延安", "陕西", "西北", 70], ["榆林", "陕西", "西北", 75],
  ["汉中", "陕西", "西北", 150], ["宝鸡", "陕西", "西北", 70], ["兰州", "甘肃", "西北", 65],
  ["敦煌", "甘肃", "西北", 110], ["嘉峪关", "甘肃", "西北", 80], ["天水", "甘肃", "西北", 70],
  ["张掖", "甘肃", "西北", 110], ["西宁", "青海", "西北", 85], ["银川", "宁夏", "西北", 75],
  ["乌鲁木齐", "新疆", "西北", 105], ["喀什", "新疆", "西北", 100], ["伊犁", "新疆", "西北", 190],
  ["吐鲁番", "新疆", "西北", 110],
  ["东莞", "广东", "华南", 40], ["惠州", "广东", "华南", 110], ["中山", "广东", "华南", 42],
  ["肇庆", "广东", "华南", 65], ["湛江", "广东", "华南", 80], ["清远", "广东", "华南", 180],
  ["韶关", "广东", "华南", 80],
  ["衡水", "河北", "华北", 65], ["唐山", "河北", "华北", 85],
  ["本溪", "辽宁", "东北", 170], ["白城", "吉林", "东北", 170], ["松原", "吉林", "东北", 100],
  ["齐齐哈尔", "黑龙江", "东北", 110],
  ["连云港", "江苏", "华东", 95], ["丽水", "浙江", "华东", 120], ["滁州", "安徽", "华东", 75],
  ["龙岩", "福建", "华东", 120], ["新乡", "河南", "华中", 85], ["周口", "河南", "华中", 80],
  ["黄冈", "湖北", "华中", 120], ["荆门", "湖北", "华中", 95],
  ["河源", "广东", "华南", 115], ["崇左", "广西", "华南", 120], ["柳州", "广西", "华南", 190],
  ["兴义", "贵州", "西南", 120], ["腾冲", "云南", "西南", 120],
  ["咸阳", "陕西", "西北", 85], ["甘南", "甘肃", "西北", 180],
  ["固原", "宁夏", "西北", 120], ["吴忠", "宁夏", "西北", 120], ["阿克苏", "新疆", "西北", 180]
].map(([city, province, region, radiusKm]) => ({ city, province, region, radiusKm }));

const cityAnchors = {
  上海: ["外滩", "豫园", "上海博物馆", "东方明珠", "上海迪士尼"],
  南京: ["中山陵", "南京博物院", "明孝陵", "夫子庙", "总统府"],
  苏州: ["拙政园", "苏州博物馆", "虎丘", "留园", "平江路"],
  无锡: ["鼋头渚", "灵山大佛", "惠山古镇", "拈花湾"],
  常州: ["中华恐龙园", "天宁寺", "淹城", "青果巷"],
  镇江: ["金山寺", "西津渡", "北固山", "焦山"],
  扬州: ["瘦西湖", "个园", "何园", "大明寺", "东关街"],
  南通: ["濠河", "狼山", "南通博物苑", "啬园"],
  徐州: ["云龙湖", "徐州博物馆", "龟山汉墓", "汉文化景区"],
  杭州: ["西湖", "灵隐寺", "西溪湿地", "良渚遗址", "中国茶叶博物馆"],
  宁波: ["天一阁", "宁波博物馆", "东钱湖", "天童寺"],
  温州: ["雁荡山", "江心屿", "楠溪江", "南麂列岛"],
  绍兴: ["鲁迅故里", "沈园", "兰亭", "大禹陵", "柯岩"],
  嘉兴: ["乌镇", "西塘", "南湖", "盐官"],
  湖州: ["南浔古镇", "莫干山", "太湖", "安吉竹博园"],
  金华: ["横店影视城", "双龙洞", "诸葛八卦村", "佛堂古镇"],
  台州: ["天台山", "神仙居", "国清寺", "大陈岛"],
  衢州: ["江郎山", "廿八都", "龙游石窟", "孔氏南宗家庙"],
  舟山: ["普陀山", "朱家尖", "东极岛", "嵊泗"],
  淄博: ["周村古商城", "齐文化博物馆", "潭溪山", "红叶柿岩"],
  潍坊: ["青州古城", "十笏园", "风筝博物馆", "沂山"],
  泰安: ["泰山", "岱庙", "太阳部落"],
  临沂: ["沂蒙山", "地下大峡谷", "王羲之故居", "竹泉村"],
  重庆: ["洪崖洞", "解放碑", "磁器口", "三峡博物馆", "武隆天生三桥"],
  成都: ["熊猫基地", "武侯祠", "杜甫草堂", "宽窄巷子", "金沙遗址"],
  乐山: ["乐山大佛", "峨眉山", "峨眉山金顶"],
  绵阳: ["越王楼", "江油李白故居", "北川羌城旅游区", "九皇山景区"],
  阿坝: ["四姑娘山", "黄龙", "若尔盖", "毕棚沟", "达古冰川"],
  九寨沟: ["九寨沟", "珍珠滩瀑布", "诺日朗瀑布", "五花海", "长海"],
  昆明: ["石林", "滇池", "云南民族村", "世博园", "翠湖"],
  大理: ["洱海", "大理古城", "苍山", "崇圣寺三塔", "喜洲"],
  丽江: ["丽江古城", "玉龙雪山", "束河古镇", "虎跳峡", "泸沽湖"],
  香格里拉: ["普达措", "松赞林寺", "独克宗古城", "虎跳峡"],
  西双版纳: ["中国科学院西双版纳热带植物园", "西双版纳野象谷", "曼听公园", "西双版纳总佛寺", "告庄西双景"],
  贵阳: ["青岩古镇", "黔灵山", "甲秀楼", "贵州省博物馆"],
  遵义: ["遵义会议会址", "赤水丹霞", "海龙屯", "茅台镇"],
  凯里: ["西江千户苗寨", "郎德上寨", "下司古镇", "青龙洞", "镇远古城"],
  拉萨: ["布达拉宫", "大昭寺", "八廓街", "色拉寺", "哲蚌寺"],
  西安: ["兵马俑", "大雁塔", "西安城墙", "陕西历史博物馆", "华清宫"],
  延安: ["宝塔山", "延安革命纪念馆", "枣园", "杨家岭", "壶口瀑布"],
  榆林: ["镇北台", "红石峡", "统万城", "波浪谷", "石峁"],
  汉中: ["汉中博物馆", "武侯祠", "张骞墓", "青木川", "黎坪"],
  宝鸡: ["法门寺", "太白山", "宝鸡青铜器博物院", "关山草原"],
  兰州: ["甘肃省博物馆", "中山桥", "白塔山", "黄河母亲"],
  敦煌: ["莫高窟", "鸣沙山", "月牙泉", "雅丹", "阳关"],
  嘉峪关: ["嘉峪关", "嘉峪关关城", "悬壁长城", "长城第一墩"],
  天水: ["麦积山石窟", "伏羲庙", "南郭寺", "仙人崖"],
  张掖: ["七彩丹霞", "大佛寺", "马蹄寺", "平山湖大峡谷"],
  西宁: ["塔尔寺", "青海省博物馆", "东关清真大寺"],
  银川: ["西夏陵", "水洞沟", "镇北堡西部影城", "贺兰山岩画"],
  乌鲁木齐: ["天池", "新疆维吾尔自治区博物馆", "天山大峡谷", "红山公园"],
  喀什: ["喀什噶尔老城", "艾提尕尔清真寺", "香妃园", "帕米尔高原"],
  伊犁: ["赛里木湖", "那拉提", "喀拉峻", "霍尔果斯", "果子沟"],
  吐鲁番: ["葡萄沟", "火焰山", "交河故城", "高昌故城", "坎儿井"],
  东莞: ["鸦片战争博物馆", "海战博物馆", "虎门炮台", "东莞可园", "松山湖", "观音山"],
  惠州: ["惠州西湖", "罗浮山", "双月湾", "巽寮湾", "南昆山"],
  中山: ["孙中山故居纪念馆", "中山詹园", "岐江公园", "孙文西路"],
  肇庆: ["七星岩", "鼎湖山", "古城墙"],
  湛江: ["湖光岩", "东海岛", "硇洲岛", "金沙湾"],
  清远: ["连州地下河", "古龙峡", "南岗千年瑶寨", "英西峰林走廊洞天仙境"],
  韶关: ["丹霞山", "南华寺", "珠玑古巷", "云门山"],
  衡水: ["衡水湖", "衡水园博园", "闾里古镇"],
  唐山: ["南湖·开滦旅游景区", "唐山南湖", "清东陵", "开滦国家矿山公园"],
  本溪: ["五女山", "本溪水洞", "关门山"],
  白城: ["大安嫩江湾", "向海自然保护区", "莫莫格国家级自然保护区"],
  松原: ["查干湖", "龙华寺", "乾安泥林"],
  齐齐哈尔: ["扎龙", "龙沙公园", "黑龙江督军署"],
  连云港: ["连岛", "花果山", "海上云台山", "连云港市博物馆"],
  丽水: ["云和梯田", "古堰画乡", "仙都", "南尖岩"],
  滁州: ["琅琊山", "醉翁亭", "明皇陵", "滁州市博物馆"],
  龙岩: ["冠豸山", "永定土楼", "古田会议会址", "长汀古城"],
  新乡: ["宝泉", "八里沟", "万仙山", "比干庙"],
  周口: ["太昊伏羲陵", "周口关帝庙", "老子故里", "弦歌台", "叶氏庄园"],
  黄冈: ["麻城龟峰山", "东坡赤壁", "天堂寨", "遗爱湖"],
  荆门: ["明显陵", "漳河", "绿林山"],
  河源: ["万绿湖", "霍山", "河源市博物馆", "龟峰塔"],
  崇左: ["花山岩画", "德天瀑布", "明仕田园", "友谊关"],
  柳州: ["程阳八寨", "龙潭公园", "柳侯祠", "三江鼓楼"],
  兴义: ["万峰林", "马岭河峡谷", "万峰湖"],
  腾冲: ["和顺古镇", "热海", "火山地热国家地质公园", "北海湿地"],
  咸阳: ["乾陵", "茂陵", "咸阳博物院", "袁家村"],
  甘南: ["冶力关", "拉卜楞寺", "扎尕那", "桑科草原"],
  固原: ["六盘山", "须弥山石窟", "火石寨"],
  吴忠: ["青铜峡黄河大峡谷", "一百零八塔", "中华黄河楼"],
  阿克苏: ["天山托木尔", "温宿大峡谷", "克孜尔千佛洞", "塔克拉玛干沙漠"]
};

// The Ministry of Culture and Tourism catalogue is used only as an editorial
// identity/ranking check. Descriptions, prices and opening times are still
// sourced separately and never inferred from a 5A designation.
const official5AAnchors = new Set([
  "衡水湖", "晋祠天龙山", "老牛湾黄河大峡谷", "大安嫩江湾", "嫩江湾旅游区", "扎龙", "扎龙国家级自然保护区", "双龙洞", "周村古商城",
  "篁岭", "宝泉", "麻城龟峰山", "万绿湖", "冠豸山", "花山岩画", "成都天台山", "万峰林",
  "乾陵", "冶力关", "六盘山", "天山托木尔", "通州大运河", "南湖开滦", "唐山南湖", "莫尔格勒河",
  "五女山", "查干湖", "西沙明珠湖", "连岛", "云和梯田", "琅琊山", "厦门园林植物园",
  "青岛奥帆海洋文化旅游区", "太昊伏羲陵", "明显陵", "凤凰古城", "程阳八寨", "天涯海角",
  "武陵山大裂谷", "四姑娘山", "和顺古镇", "延川黄河乾坤湾", "青铜峡黄河大峡谷"
]);

const curatedAnchorOverrides = [
  { city: "白城", name: "大安嫩江湾", coord: { lat: 45.52881, lng: 124.288247 }, category: "自然", url: "https://www.openstreetmap.org/way/1028850124" },
  { city: "齐齐哈尔", name: "扎龙国家级自然保护区", coord: { lat: 47.203203, lng: 124.235558 }, category: "自然", url: "https://ditu.amap.com/place/B01C400MXJ" },
  { city: "丽水", name: "云和梯田", coord: { lat: 28.048612, lng: 119.487375 }, category: "山水", url: "https://ditu.amap.com/place/B024215MX7" },
  { city: "黄冈", name: "麻城龟峰山", coord: { lat: 31.107193, lng: 115.225551 }, category: "山水", url: "https://www.openstreetmap.org/way/929456680" },
  { city: "河源", name: "万绿湖", coord: { lat: 23.915855, lng: 114.53823 }, category: "山水", url: "https://www.openstreetmap.org/relation/397886" },
  { city: "柳州", name: "程阳八寨", coord: { lat: 25.905141, lng: 109.644814 }, category: "古镇", url: "https://www.openstreetmap.org/relation/11487730" },
  { city: "腾冲", name: "和顺古镇", coord: { lat: 25.009423, lng: 98.456754 }, category: "古镇", url: "https://ditu.amap.com/place/B036B005AX" },
  { city: "甘南", name: "冶力关", coord: { lat: 34.964398, lng: 103.660491 }, category: "山水", url: "https://www.openstreetmap.org/relation/11835235" },
  { city: "吴忠", name: "青铜峡黄河大峡谷", coord: { lat: 37.883645, lng: 105.991775 }, category: "山水", url: "https://ditu.amap.com/place/B03B90M3BZ" }
];

const cityExclusions = new Map([
  ["本溪", /本溪湖煤矿/],
  ["河源", /顺景花园/],
  ["吴忠", /银川当代美术馆|永宁县多宝塔/],
  ["阿克苏", /天山山脈|天山山脉|汗腾格里峰|托木尔峰/]
]);
// Every destination gets a second pass for missing editorial anchors. This is
// intentionally low frequency (cached and throttled) and prevents a dense but
// mediocre local dataset from crowding out the landmarks travellers expect.
const forceLandmarkLookup = new Set(destinations.map((destination) => destination.city));

const cityRows = JSON.parse(await cachedText(
  "city-geo.json",
  "https://raw.githubusercontent.com/88250/city-geo/master/data.json"
));
for (const destination of destinations) destination.coord = cityCentre(destination, cityRows);
const administrativeCentres = buildAdministrativeCentres(cityRows);

const audialaRows = parseCSV(await cachedText(
  "audiala-places.csv",
  "https://raw.githubusercontent.com/audiala/open-data/main/data/audiala-places.csv"
)).filter((row) => row.country_iso2 === "CN");

const candidatesByCity = new Map(destinations.map((destination) => [destination.city, []]));
for (let offset = 0; offset < destinations.length; offset += 4) {
  const batch = destinations.slice(offset, offset + 4);
  const settled = await Promise.allSettled(batch.map(wikidataAround));
  settled.forEach((result, index) => {
    if (result.status === "rejected") throw result.reason;
    for (const binding of result.value.results?.bindings || []) {
      const candidate = wikidataCandidate(binding);
      const owner = candidate ? nearestDestination(candidate.coord) : null;
      const target = batch[index];
      const isNamedAnchor = candidate
        && anchorBonus(target.city, candidate.name) > 0
        && haversineKm(target.coord, candidate.coord) <= target.radiusKm;
      if (candidate && (owner?.city === target.city || isNamedAnchor)) {
        mergeCandidate(candidatesByCity.get(batch[index].city), candidate);
      }
    }
  });
  console.log("Wikidata：" + Math.min(offset + 4, destinations.length) + "/" + destinations.length + " 个目的地已读取");
  await delay(220);
}

for (const row of audialaRows) {
  const coord = coordinate(Number(row.latitude), Number(row.longitude));
  if (!coord) continue;
  const destination = nearestDestination(coord);
  if (!destination) continue;
  const name = cleanName(row.name_zh || row.name_en);
  if (!usableName(name)) continue;
  const category = categoryFromAudiala(row.category);
  if (!category) continue;
  mergeCandidate(candidatesByCity.get(destination.city), {
    name,
    coord,
    category,
    opening: null,
    wikidata: row.wikidata_id,
    wikipedia: null,
    guideURL: row.url_zh || row.url_en || null,
    source: "Audiala",
    baseScore: 210 + Math.min(240, finite(row.sitelinks) * 3) + Math.min(90, Math.log1p(finite(row.wikidata_pagerank)) * 18),
    sitelinks: finite(row.sitelinks)
  });
}

for (const place of curatedAnchorOverrides) {
  const destination = destinations.find((candidate) => candidate.city === place.city);
  if (!destination || haversineKm(destination.coord, place.coord) > destination.radiusKm) {
    throw new Error(place.city + "/" + place.name + " 的校验坐标超出目的地范围");
  }
  mergeCandidate(candidatesByCity.get(place.city), {
    name: place.name,
    coord: place.coord,
    category: place.category,
    opening: null,
    wikidata: null,
    wikipedia: null,
    guideURL: place.url,
    source: "文化和旅游部名录 + 公开地图坐标校验",
    baseScore: 420,
    sitelinks: 0
  });
}

for (const binding of await wikidataAnchors()) {
  const name = cleanName(binding.label?.value);
  const point = String(binding.coord?.value || "").match(/Point\(([-\d.]+) ([-\d.]+)\)/);
  const coord = point ? coordinate(Number(point[2]), Number(point[1])) : null;
  const qid = String(binding.item?.value || "").match(/Q\d+$/)?.[0] || null;
  if (!name || !coord || !qid) continue;
  for (const destination of destinations) {
    if (anchorBonus(destination.city, name) <= 0) continue;
    if (haversineKm(destination.coord, coord) > destination.radiusKm) continue;
    mergeCandidate(candidatesByCity.get(destination.city), {
      name,
      coord,
      category: categoryFromAnchor(name),
      opening: null,
      wikidata: qid,
      wikipedia: null,
      guideURL: "https://www.wikidata.org/wiki/" + qid,
      source: "Wikidata 城市地标校准",
      baseScore: 185,
      sitelinks: finite(binding.sitelinks?.value)
    });
  }
}

for (const destination of destinations) {
  const candidates = candidatesByCity.get(destination.city);
  const forceLookup = forceLandmarkLookup.has(destination.city);
  if (candidates.length >= 8 && !forceLookup) continue;
  for (const anchor of cityAnchors[destination.city] || []) {
    if (candidates.some((candidate) => namesMatch(anchor, candidate.name))) continue;
    const candidate = await nominatimLandmark(anchor, destination);
    if (candidate) mergeCandidate(candidates, candidate);
    if (!forceLookup && candidates.length >= 8) break;
  }
  console.log(destination.city + " 长尾补充：" + candidates.length + " 个候选点");
}

const cities = destinations.map((destination) => {
  const candidates = candidatesByCity.get(destination.city)
    .filter((candidate) => !cityExclusions.get(destination.city)?.test(candidate.name))
    .map((candidate) => ({
      ...candidate,
      score: candidate.baseScore
        + Math.min(360, candidate.sitelinks * 4)
        + anchorBonus(destination.city, candidate.name)
        + official5ABonus(candidate.name)
        - Math.min(220, haversineKm(destination.coord, candidate.coord) / destination.radiusKm * 180)
    }))
    .sort((a, b) => b.score - a.score || a.name.localeCompare(b.name, "zh-CN"));

  const selected = balancedSelection(candidates, 10, destination.city);
  if (selected.length < 3) throw new Error(destination.city + " 只有 " + selected.length + " 个可用景点，请检查开放数据覆盖");
  console.log(destination.city + "：" + selected.length + " 处；首选 " + selected.slice(0, 3).map((item) => item.name).join("、"));
  return guideCity(destination, selected);
});

writeFileSync(outputPath, JSON.stringify({ cities }, null, 2) + "\n");
console.log("已写入 " + outputPath + "：" + cities.length + " 个国内目的地、" + cities.reduce((sum, city) => sum + city.places.length, 0) + " 处景点。");

async function cachedText(filename, url) {
  const path = join(cacheRoot, filename);
  if (existsSync(path) && readFileSync(path).length > 100) return readFileSync(path, "utf8");
  const response = await fetchWithRetry(url, { headers: requestHeaders() }, 3);
  const text = await response.text();
  if (text.length < 100) throw new Error(url + " 返回内容过短");
  writeFileSync(path, text);
  return text;
}

async function wikidataAround(destination) {
  const cachePath = join(cacheRoot, "wikidata-around-" + destination.city + ".json");
  if (existsSync(cachePath)) return JSON.parse(readFileSync(cachePath, "utf8"));
  const radius = Math.min(destination.radiusKm, 140);
  const point = destination.coord.lng + " " + destination.coord.lat;
  const query = "SELECT ?item ?itemLabel ?coord ?sitelinks ?article (GROUP_CONCAT(DISTINCT ?typeLabel; separator=\"|\") AS ?types) WHERE { "
    + "SERVICE wikibase:around { ?item wdt:P625 ?coord . bd:serviceParam wikibase:center \"Point(" + point + ")\"^^geo:wktLiteral . bd:serviceParam wikibase:radius \"" + radius + "\" . } "
    + "?item wikibase:sitelinks ?sitelinks . ?article schema:about ?item ; schema:isPartOf <https://zh.wikipedia.org/> . "
    + "OPTIONAL { ?item wdt:P31 ?type . ?type rdfs:label ?typeLabel . FILTER(LANG(?typeLabel)=\"zh\") } "
    + "SERVICE wikibase:label { bd:serviceParam wikibase:language \"zh,en\". ?item rdfs:label ?itemLabel . } "
    + "} GROUP BY ?item ?itemLabel ?coord ?sitelinks ?article ORDER BY DESC(?sitelinks) LIMIT 180";
  const response = await fetchWithRetry("https://query.wikidata.org/sparql", {
    method: "POST",
    headers: { ...requestHeaders(), "Content-Type": "application/x-www-form-urlencoded", Accept: "application/sparql-results+json" },
    body: new URLSearchParams({ query, format: "json" })
  }, 3);
  const payload = await response.json();
  writeFileSync(cachePath, JSON.stringify(payload));
  return payload;
}

async function wikidataAnchors() {
  const names = [...new Set(Object.values(cityAnchors).flat())];
  const bindings = [];
  for (let offset = 0; offset < names.length; offset += 120) {
    const batchNumber = Math.floor(offset / 120) + 1;
    const cachePath = join(cacheRoot, "wikidata-anchors-v4-" + batchNumber + ".json");
    let payload;
    if (existsSync(cachePath)) {
      payload = JSON.parse(readFileSync(cachePath, "utf8"));
    } else {
      const values = names.slice(offset, offset + 120)
        .map((name) => "\"" + name.replace(/[\"\\]/g, "") + "\"@zh")
        .join(" ");
      const query = "SELECT ?item ?label ?coord ?sitelinks WHERE { VALUES ?label { " + values
        + " } ?item rdfs:label ?label ; wdt:P625 ?coord ; wikibase:sitelinks ?sitelinks . } ORDER BY DESC(?sitelinks)";
      const response = await fetchWithRetry("https://query.wikidata.org/sparql", {
        method: "POST",
        headers: { ...requestHeaders(), "Content-Type": "application/x-www-form-urlencoded", Accept: "application/sparql-results+json" },
        body: new URLSearchParams({ query, format: "json" })
      }, 3);
      payload = await response.json();
      writeFileSync(cachePath, JSON.stringify(payload));
    }
    bindings.push(...(payload.results?.bindings || []));
  }
  console.log("Wikidata 城市地标：" + bindings.length + " 个精确匹配");
  return bindings;
}

async function nominatimLandmark(anchor, destination) {
  const cacheName = "nominatim-" + destination.city + "-" + anchor.replace(/[^\p{L}\p{N}]+/gu, "_") + ".json";
  const cachePath = join(cacheRoot, cacheName);
  let rows;
  if (existsSync(cachePath)) {
    rows = JSON.parse(readFileSync(cachePath, "utf8"));
  } else {
    const endpoint = new URL("https://nominatim.openstreetmap.org/search");
    endpoint.searchParams.set("q", anchor + " " + destination.city + " " + destination.province + " 中国");
    endpoint.searchParams.set("format", "jsonv2");
    endpoint.searchParams.set("limit", "4");
    endpoint.searchParams.set("accept-language", "zh-CN");
    const response = await fetchWithRetry(endpoint, { headers: requestHeaders() }, 2);
    rows = await response.json();
    writeFileSync(cachePath, JSON.stringify(rows));
    await delay(1_050);
  }
  const row = rows
    .map((item) => ({ item, coord: coordinate(Number(item.lat), Number(item.lon)) }))
    .filter((item) => item.coord
      && usableNominatimRow(item.item, anchor)
      && haversineKm(destination.coord, item.coord) <= destination.radiusKm)
    .sort((a, b) => finite(b.item.importance) - finite(a.item.importance))[0];
  if (!row) return null;
  const returnedName = cleanName(row.item.name || anchor);
  // Search engines occasionally return an entrance, visitor centre or the
  // surrounding administrative district for a well-known landmark. Keep its
  // coordinate, but retain the requested landmark name in that case.
  const displayName = usableName(returnedName) ? returnedName : anchor;
  return {
    name: displayName,
    coord: row.coord,
    category: categoryFromAnchor(anchor),
    opening: null,
    wikidata: firstQID(row.item.extratags?.wikidata),
    wikipedia: cleanOptional(row.item.extratags?.wikipedia),
    guideURL: row.item.osm_type && row.item.osm_id
      ? "https://www.openstreetmap.org/" + row.item.osm_type + "/" + row.item.osm_id
      : sourceURLs.osmCopyright,
    source: "OpenStreetMap 地标补充",
    baseScore: 155 + Math.min(70, finite(row.item.importance) * 220),
    sitelinks: 0
  };
}

function usableNominatimRow(item, anchor) {
  const category = String(item.category || "");
  const type = String(item.type || "");
  const returnedName = cleanName(item.name);
  if (/school|kindergarten|residential|commercial|industrial|retail|railway|boundary|office|shop/.test(category + " " + type)) return false;
  if (["place", "information", "highway"].includes(category) && !namesMatch(anchor, returnedName)) return false;
  return true;
}

async function fetchWithRetry(url, options, attempts) {
  let lastError;
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      const response = await fetch(url, { ...options, signal: AbortSignal.timeout(150_000) });
      if (!response.ok) throw new Error("HTTP " + response.status + " @ " + url);
      return response;
    } catch (error) {
      lastError = error;
      if (attempt < attempts) await delay(700 * attempt);
    }
  }
  throw lastError;
}

function requestHeaders() {
  return { "User-Agent": "AnyTravelOpenSource/0.8 (+https://github.com/Rseam-07/AnyTravel)" };
}

function cityCentre(destination, rows) {
  const cityNeedle = stripAdmin(destination.city);
  const provinceNeedle = stripAdmin(destination.province);
  const candidates = rows.filter((row) => {
    if (stripAdmin(row.province) !== provinceNeedle) return false;
    return stripAdmin(row.city).startsWith(cityNeedle)
      || stripAdmin(row.area).startsWith(cityNeedle)
      || stripAdmin(row.province).startsWith(cityNeedle);
  });
  candidates.sort((a, b) => centreRank(a, cityNeedle) - centreRank(b, cityNeedle));
  const row = candidates[0];
  const coord = coordinate(Number(row?.lat), Number(row?.lng));
  if (!coord) throw new Error("找不到 " + destination.city + " 的城市中心");
  return coord;
}

function centreRank(row, cityNeedle) {
  if (!row.area && stripAdmin(row.city) === cityNeedle) return 0;
  if (!row.area && stripAdmin(row.province) === cityNeedle) return 1;
  if (stripAdmin(row.area) === cityNeedle) return 2;
  if (stripAdmin(row.city).startsWith(cityNeedle)) return 3;
  return 9;
}

function buildAdministrativeCentres(rows) {
  const centres = destinations.map((destination) => ({
    city: destination.city,
    coord: destination.coord,
    radiusKm: destination.radiusKm,
    target: true
  }));
  const targetNames = new Set(destinations.map((destination) => stripAdmin(destination.city)));
  for (const row of rows) {
    if (row.area) continue;
    const city = stripAdmin(row.city === "市辖区" ? row.province : row.city);
    const coord = coordinate(Number(row.lat), Number(row.lng));
    if (!city || !coord || targetNames.has(city)) continue;
    if (destinations.some((destination) => haversineKm(coord, destination.coord) < 18)) continue;
    centres.push({ city, coord, radiusKm: Number.POSITIVE_INFINITY, target: false });
  }
  centres.push(
    { city: "香港", coord: { lat: 22.3193, lng: 114.1694 }, radiusKm: Number.POSITIVE_INFINITY, target: false },
    { city: "澳门", coord: { lat: 22.1987, lng: 113.5439 }, radiusKm: Number.POSITIVE_INFINITY, target: false }
  );
  return centres;
}

function stripAdmin(value) {
  return String(value || "")
    .replace(/壮族自治区|回族自治区|维吾尔自治区|藏族羌族自治州|哈萨克自治州|傣族自治州|白族自治州|藏族自治州|苗族侗族自治州/g, "")
    .replace(/省|市|地区|自治州|自治区|盟|县|区$/g, "");
}

function wikidataCandidate(binding) {
  const name = cleanName(binding.itemLabel?.value);
  if (!usableName(name)) return null;
  const point = String(binding.coord?.value || "").match(/Point\(([-\d.]+) ([-\d.]+)\)/);
  const coord = point ? coordinate(Number(point[2]), Number(point[1])) : null;
  if (!coord) return null;
  const types = cleanName(binding.types?.value);
  const category = categoryFromWikidata(types, name);
  if (!category) return null;
  const sitelinks = finite(binding.sitelinks?.value);
  const qid = String(binding.item?.value || "").match(/Q\d+$/)?.[0] || null;
  let score = 38;
  if (/国家5A级旅游景区|世界遗产|全国重点文物保护单位/.test(types)) score += 145;
  if (/博物馆|美術館|美术馆|考古遗址|宮殿|宫殿|佛寺|道观|主教座堂|国家公园|保护区/.test(types)) score += 85;
  if (/故宫|长城|兵马俑|西湖|石窟|古城|古镇|国家公园|风景区|博物馆|寺|塔|陵|山|湖|岛/.test(name)) score += 32;
  return {
    name,
    coord,
    category,
    opening: null,
    wikidata: qid,
    wikipedia: null,
    guideURL: cleanOptional(binding.article?.value),
    source: "Wikidata / 中文维基百科",
    baseScore: score,
    sitelinks
  };
}

function categoryFromWikidata(types, name) {
  const hardRejected = /体育事件|体育赛事|賽季|战争|戰役|事变|自然语言|現代語言|历史上的中华国家|歷史國家|諸侯國|王國|政治实体|地质年代|地質年代|地质时期|地質時期|地质学期|地層階段|地震|自然灾害|災害|考古學文化|文化地區|交通线路|鐵路線|地铁路线|地下鐵路線|港口|河流|自然水道|公路橋|公路桥|铁路桥|特大桥|体育中心|體育中心|体育场|體育場|竞技场|競技場|超级计算机|電視頻道|电视频道|电视台|電視台|(^|\|)(组|組)(\||$)/;
  const rejected = /机场|鐵路車站|铁路车站|地铁站|地鐵|道路|高速公路|隧道|大學|大学|学校|行政领土|行政領土|市辖区|地级市|县级市|省|县|镇|乡|街道|人類聚居地|人类聚居地|体育赛事|賽季|战争|戰役|事变|語言|语言|历史国家|王國|企业|飯店|酒店/;
  const positive = /旅游|景区|世界遗产|文化遗产|文物保护|博物|美術|美术|纪念馆|紀念館|公园|公園|园林|園林|花园|植物園|動物園|动物园|水族馆|主題公園|主题公园|游乐园|古迹|遺址|遗址|考古|宮殿|宫殿|寺|庙|教堂|清真寺|道观|陵墓|坟墓|墳場|纪念物|紀念物|纪念碑|塔|观光塔|城堡|堡垒|城门|城市門|古建筑|建造物群|建築群|保护区|保護區|自然保护|山峰|山脉|山脈|湖泊|水庫|瀑布|岛屿|島|海滩|廣場|广场|剧场|劇場|歌剧院|橋|桥|度假村|歷史建築|历史建筑/;
  const nameSignal = /外滩|步行街|古街|老街|古城|古镇|苗寨|侗寨|村寨|风景|景区|博物馆|美术馆|纪念馆|公园|园林|花园|寺|庙|教堂|清真寺|道观|塔|宫|陵|墓|遗址|石窟|长城|山|峰|峡|谷|瀑布|洞|湖|海|滩|岛|广场|大剧院|乐园|动物园|植物园|湿地|水库/;
  if (hardRejected.test(types) && !/博物馆|博物館|纪念馆|紀念館|遗址|遺址/.test(types + name)) return null;
  if (!positive.test(types) && !nameSignal.test(name)) return null;
  if (rejected.test(types) && !positive.test(types)) return null;
  if (/博物|纪念馆|紀念館/.test(types + name)) return "博物馆";
  if (/美術|美术|艺术馆/.test(types + name)) return "美术馆";
  if (/动物园|動物園/.test(types + name)) return "动物园";
  if (/主题公园|主題公園|游乐园|乐园/.test(types + name)) return "乐园";
  if (/园林|園林|花园|植物園|植物园/.test(types + name)) return "园林";
  if (/公园|公園|保护区|保護區|自然保护|湿地/.test(types + name)) return "自然";
  if (/寺|庙|教堂|清真寺|道观|宗教/.test(types + name)) return "宗教";
  if (/古镇|古城|历史街区|古街|老街|苗寨|侗寨|村寨/.test(name)) return "古镇";
  if (/海|滩|岛|島/.test(name) || /海滩|岛屿|島/.test(types)) return "海滨";
  if (/山|峰|峡|谷|瀑布|洞|湖|草原|沙漠|水库/.test(name) || /山峰|山脉|山脈|湖泊|水庫|瀑布/.test(types)) return "山水";
  if (/广场|廣場|剧场|劇場|歌剧院|步行街|外滩/.test(types + name)) return "城市";
  return "古迹";
}

function categoryFromAudiala(category) {
  const map = {
    museum: "博物馆", gallery: "美术馆", garden: "园林", park: "公园", "botanical-garden": "园林",
    zoo: "动物园", "amusement-park": "乐园", beach: "海滨", island: "海滨", lake: "山水", mountain: "山水",
    waterfall: "山水", cave: "山水", temple: "宗教", church: "宗教", cathedral: "宗教", mosque: "宗教",
    monastery: "宗教", "religious-site": "宗教", street: "城市", square: "城市", neighbourhood: "城市",
    theatre: "城市", "opera-house": "城市", market: "城市", attraction: "古迹", palace: "古迹",
    monument: "古迹", fortification: "古迹", castle: "古迹", "city-gate": "古迹",
    memorial: "古迹", "archaeological-site": "古迹", canal: "古迹", lighthouse: "古迹", fountain: "古迹"
  };
  return map[category] || null;
}

function categoryFromAnchor(name) {
  if (/博物馆|博物院|纪念馆|故居|会址/.test(name)) return "博物馆";
  if (/美术馆|艺术馆/.test(name)) return "美术馆";
  if (/动物园/.test(name)) return "动物园";
  if (/乐园|影视城/.test(name)) return "乐园";
  if (/园林|花园|植物园|个园|何园|拙政园|留园/.test(name)) return "园林";
  if (/寺|庙|教堂|清真寺|道观|佛/.test(name)) return "宗教";
  if (/古城|古镇|古街|老街|苗寨|侗寨|村寨|故城/.test(name)) return "古镇";
  if (/海|滩|岛|湾/.test(name)) return "海滨";
  if (/山|峰|峡|谷|瀑布|洞|湖|草原|沙漠|湿地|丹霞|石林|天池|洱海/.test(name)) return "山水";
  if (/街|巷|广场|外滩|夜市/.test(name)) return "城市";
  return "古迹";
}

function nearestDestination(coord) {
  let best = null;
  for (const destination of administrativeCentres) {
    const distanceKm = haversineKm(coord, destination.coord);
    if (!best || distanceKm < best.distanceKm) best = { destination, distanceKm };
  }
  return best?.destination.target && best.distanceKm <= best.destination.radiusKm ? best.destination : null;
}

function anchorBonus(city, name) {
  const index = (cityAnchors[city] || []).findIndex((anchor) => namesMatch(anchor, name));
  return index < 0 ? 0 : 760 - index * 70;
}

function official5ABonus(name) {
  return [...official5AAnchors].some((anchor) => namesMatch(anchor, name)) ? 900 : 0;
}

function namesMatch(lhs, rhs) {
  const left = canonicalName(lhs);
  const right = canonicalName(rhs);
  return left === right || (Math.min(left.length, right.length) >= 3 && (left.includes(right) || right.includes(left)));
}

function mergeCandidate(candidates, incoming) {
  const key = canonicalName(incoming.name);
  const index = candidates.findIndex((current) => {
    const currentKey = canonicalName(current.name);
    return currentKey === key || (Math.min(currentKey.length, key.length) >= 5 && (currentKey.includes(key) || key.includes(currentKey)));
  });
  if (index < 0) candidates.push(incoming);
  else {
    const current = candidates[index];
    candidates[index] = {
      ...(incoming.baseScore > current.baseScore ? current : incoming),
      ...(incoming.baseScore > current.baseScore ? incoming : current),
      baseScore: Math.max(current.baseScore, incoming.baseScore),
      sitelinks: Math.max(current.sitelinks || 0, incoming.sitelinks || 0),
      guideURL: current.guideURL || incoming.guideURL,
      wikipedia: current.wikipedia || incoming.wikipedia,
      wikidata: current.wikidata || incoming.wikidata,
      opening: current.opening || incoming.opening,
      source: [...new Set([current.source, incoming.source])].join(" + ")
    };
  }
}

function balancedSelection(candidates, limit, city) {
  const selected = [];
  const pool = [...candidates];
  const maximumPerCategory = 4;
  while (pool.length && selected.length < limit) {
    const index = pool.findIndex((candidate) =>
      selected.filter((item) => item.category === candidate.category).length < maximumPerCategory
      && !selected.some((item) => sameAttraction(item.name, candidate.name, city))
    );
    if (index < 0) break;
    selected.push(pool.splice(index, 1)[0]);
  }
  return selected;
}

function sameAttraction(lhs, rhs, city) {
  const left = semanticName(lhs, city);
  const right = semanticName(rhs, city);
  if (!left || !right) return false;
  if (left === right) return true;
  // Longer catalogue labels often wrap the same physical attraction in a
  // "historic complex" or "scenic area" name. Avoid showing both as two stops.
  return Math.min(left.length, right.length) >= 4 && (left.includes(right) || right.includes(left));
}

function semanticName(value, city) {
  const cityName = canonicalName(city);
  return canonicalName(value)
    .replace(new RegExp("^" + cityName), "")
    .replace(/\u4e3b\u9898\u4e50\u56ed|\u4e50\u56ed|\u5ea6\u5047\u533a|\u5386\u53f2\u5efa\u7b51\u7fa4|\u5efa\u7b51\u7fa4|\u5e7f\u573a|\u6e38\u5ba2(\u670d\u52a1)?\u4e2d\u5fc3/g, "");
}

function guideCity(destination, selected) {
  const places = selected.map((place, index) => ({
    name: place.name,
    coord: place.coord,
    category: place.category,
    stayMinutes: stayMinutesFor(place.category, place.name),
    tier: index < 2 ? "必去" : index < 7 ? "推荐" : "顺路",
    ticket: "票价、余票、预约与临时开放以出发前实时查询为准",
    best: bestTimeFor(place.category),
    openingHoursWeek: place.opening || undefined,
    tags: [
      place.source + " 地点资料",
      official5ABonus(place.name) > 0 ? "文化和旅游部 5A 名录校验" : null,
      place.sitelinks ? "公开热度信号 " + place.sitelinks : null,
      place.opening ? "开放参考 " + place.opening : null
    ].filter(Boolean)
  }));
  const guideSources = selected.flatMap((place) => [
    place.guideURL,
    wikipediaURL(place.wikipedia),
    place.wikidata ? "https://www.wikidata.org/wiki/" + place.wikidata : null
  ]).filter(Boolean).slice(0, 8);
  return {
    city: destination.city,
    province: destination.province,
    region: destination.region,
    country: "中国",
    coord: destination.coord,
    tripDays: suggestedDays(places),
    sense: destination.city + "的候选点按公开热度、地点类型和空间位置共同筛选；先保留代表性停留，再由当天交通、天气与开放条件收拢。",
    places,
    patterns: routePatterns(destination.coord, places),
    sources: [...new Set([
      sourceURLs.osmCopyright,
      sourceURLs.wikidata,
      sourceURLs.cityGeo,
      ...(selected.some((place) => place.source.includes("Audiala")) ? [sourceURLs.audiala] : []),
      ...(selected.some((place) => official5ABonus(place.name) > 0)
        ? [sourceURLs.mctCatalogue, sourceURLs.mct2024February, sourceURLs.mct2024December]
        : []),
      ...guideSources
    ])]
  };
}

function routePatterns(center, places) {
  const remaining = [...places];
  const ordered = [];
  let cursor = center;
  while (remaining.length) {
    remaining.sort((a, b) => haversineKm(cursor, a.coord) - haversineKm(cursor, b.coord));
    const next = remaining.shift();
    ordered.push(next);
    cursor = next.coord;
  }
  return [
    "D1 " + ordered.slice(0, 3).map((place) => place.name).join("→") + "；D2 " + ordered.slice(3, 6).map((place) => place.name).join("→") + "（实际按日期、营业与天气重排）"
  ];
}

function stayMinutesFor(category, name) {
  if (/迪士尼|欢乐谷|环球影城|大型景区|国家公园/.test(name)) return 360;
  if (["自然", "山水", "海滨", "古镇", "动物园", "乐园"].includes(category)) return 180;
  if (["博物馆", "美术馆", "园林", "公园", "亲子"].includes(category)) return 120;
  if (["城市", "宗教"].includes(category)) return 75;
  return 90;
}

function bestTimeFor(category) {
  if (["山水", "海滨", "宗教"].includes(category)) return "上午";
  if (["博物馆", "美术馆", "亲子", "动物园", "乐园"].includes(category)) return "全天";
  if (["古镇", "城市"].includes(category)) return "傍晚";
  return "白天";
}

function suggestedDays(places) {
  const heavy = places.filter((place) => place.stayMinutes >= 180).length;
  return heavy >= 5 ? "3-5天" : heavy >= 3 ? "2-4天" : "2-3天";
}

function wikipediaURL(value) {
  if (!value) return null;
  const split = value.indexOf(":");
  if (split <= 0) return null;
  const language = value.slice(0, split);
  const title = value.slice(split + 1);
  return "https://" + language + ".wikipedia.org/wiki/" + encodeURIComponent(title.replace(/ /g, "_"));
}

function usableName(name) {
  if (name.length < 2 || !/[\u3400-\u9fff]/.test(name)) return false;
  if (/游客(服务)?中心|服务中心|售票处|检票口|停车场|卫生间|厕所|管理处|派出所|消防|医院|酒店|宾馆|民宿|餐厅|公司|集团|学校|中学|小学|学院|大学|机场|火车站|汽车站|地铁站|公交站|收费站|入口|出口|大门|办公楼|住宅|小区|社区|港口|高速公路|环线高速|(^|[^古老])站$|大桥|特大桥|赛车场|賽車場|体育中心|體育中心|体育场|體育場|万达广场|时代广场|城市广场|市民广场|广场主塔|购物中心|商场|苏宁|恒隆广场|万象城|太古里|印象城|银泰城|大悦城|来福士|事件|案件|打人|袭击|疫情|爆炸|事故|灾害|火灾|踩踏|年.*赛|世界杯|大奖赛|太湖之光|丘陵$/.test(name)) return false;
  if (/(市|区|县|镇|乡|盟|地区|自治州|街道办事处|街道|州|组)$/.test(name)) return false;
  return true;
}

function firstQID(value) {
  return String(value || "").match(/Q\d+/)?.[0] || null;
}

function coordinate(lat, lng) {
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 85 || Math.abs(lng) > 180) return null;
  return { lat: Number(lat.toFixed(6)), lng: Number(lng.toFixed(6)) };
}

function haversineKm(a, b) {
  const radians = (degrees) => degrees * Math.PI / 180;
  const dLat = radians(b.lat - a.lat);
  const dLon = radians(b.lng - a.lng);
  const sinLat = Math.sin(dLat / 2);
  const sinLon = Math.sin(dLon / 2);
  const h = sinLat * sinLat + Math.cos(radians(a.lat)) * Math.cos(radians(b.lat)) * sinLon * sinLon;
  return 6371 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

function parseCSV(text) {
  const rows = [];
  let row = [];
  let field = "";
  let quoted = false;
  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    if (quoted) {
      if (char === '"' && text[index + 1] === '"') { field += '"'; index += 1; }
      else if (char === '"') quoted = false;
      else field += char;
    } else if (char === '"') quoted = true;
    else if (char === ",") { row.push(field); field = ""; }
    else if (char === "\n") { row.push(field.replace(/\r$/, "")); rows.push(row); row = []; field = ""; }
    else field += char;
  }
  if (field || row.length) { row.push(field); rows.push(row); }
  const headers = rows.shift() || [];
  return rows.filter((values) => values.length >= headers.length).map((values) => Object.fromEntries(headers.map((header, index) => [header, values[index]])));
}

function canonicalName(value) {
  const folded = cleanName(value).toLowerCase().replace(/[東濕園館臺關門觀龍國樂麗廣灣舊縣區鎮島禪]/g, (character) => ({
    東: "东", 濕: "湿", 園: "园", 館: "馆", 臺: "台", 關: "关", 門: "门", 觀: "观", 龍: "龙",
    國: "国", 樂: "乐", 麗: "丽", 廣: "广", 灣: "湾", 舊: "旧", 縣: "县", 區: "区", 鎮: "镇", 島: "岛", 禪: "禅"
  })[character]);
  return folded.replace(/风景名胜区|旅游景区|景区|公园|博物馆|纪念馆/g, "").replace(/[\s()（）·—_\-]/g, "");
}

function cleanName(value) {
  return String(value || "").replace(/\s+/g, " ").trim();
}

function cleanOptional(value) {
  const text = cleanName(value);
  return text || null;
}

function finite(value) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? number : 0;
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
