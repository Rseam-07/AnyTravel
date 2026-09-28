// Run against a local Vite server; PLAYWRIGHT_MODULE can point at an existing installation.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const out = path.resolve(__dirname, '../../output/planner-rethink');
const base = process.env.PLANNER_QA_URL || 'http://127.0.0.1:5190';
fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(out+'/browser-checks.json', JSON.stringify({ status:'running', startedAt:new Date().toISOString() }, null, 2));
const savedTrip = async page => {
  // Autosave is intentionally debounced by 500 ms. Observe committed state, not a stale snapshot.
  await page.waitForTimeout(650);
  return page.evaluate(() => JSON.parse(localStorage.getItem('anytravel-web:current-trip')).trips[0]);
};
(async () => {
  const browser = await chromium.launch({headless:true, channel:'chrome'});
  const page = await browser.newPage({viewport:{width:1440,height:960}});
  const errors = []; page.on('pageerror', e => errors.push(e.message));
  await page.goto(base);
  await page.getByRole('button',{name:'苏州',exact:true}).click();
  await page.getByLabel('出发日期',{exact:true}).fill('2026-10-06');
  await page.getByLabel('首日几点能开始逛').fill('13:00');
  await page.getByLabel('末日几点结束游览').fill('16:00');
  await page.getByRole('radio',{name:'适中 游览与留白兼顾'}).click();
  await page.screenshot({path:out+'/desktop-brief.png'});
  await page.getByRole('button',{name:'生成我的路线',exact:true}).click();
  await page.getByRole('heading',{name:/一带/}).waitFor();
  await page.locator('.map-pin').first().waitFor({timeout:30000}); await page.locator('[data-map-ready=true]').waitFor({timeout:30000}); await page.waitForTimeout(600);
  fs.writeFileSync(out+'/desktop-plan.txt', await page.locator('.plan-panel').innerText());
  const saved = await page.evaluate(() => JSON.parse(localStorage.getItem('anytravel-web:current-trip')).trips[0]);
  fs.writeFileSync(out+'/suzhou-plan.json',JSON.stringify(saved,null,2));
  await page.screenshot({path:out+'/desktop-plan.png'});
  await page.getByRole('radio',{name:/第 2 天/}).click();
  await page.waitForTimeout(1200);
  await page.screenshot({path:out+'/desktop-day2.png'});
  await page.getByRole('radio',{name:/第 1 天/}).click();
  const motionSamples = await page.evaluate(async () => {
    const values = [];
    for(let i=0;i<35;i++) { await new Promise(requestAnimationFrame); values.push(document.querySelector('.day-switcher .motion-tab-thumb').getBoundingClientRect().x); }
    return values;
  });
  if(new Set(motionSamples.map(x=>x.toFixed(1))).size < 3) throw Error('Day selector has no spring transition');
  // Completion is bounded in wall time; 35 frames can be < 300 ms on ProMotion.
  await page.waitForFunction(() => Math.abs(document.querySelector('.day-switcher .motion-tab-thumb').getBoundingClientRect().x - document.querySelector('.day-switcher [aria-checked=true]').getBoundingClientRect().x) <= 0.5, null, { timeout: 2000 });
  const motionAligned = await page.evaluate(() => { const x=document.querySelector('.day-switcher .motion-tab-thumb').getBoundingClientRect().x; const y=document.querySelector('.day-switcher [aria-checked=true]').getBoundingClientRect().x; return Math.abs(x-y); });
  if(motionAligned>0.5) throw Error('Spring failed to settle');
  await page.screenshot({path:out+'/desktop-plan.png'});
  const original = await savedTrip(page);
  let replacementWorked = false;
  const replacementAttempts = [];
  for (let stop = 0; stop < original.snapshot.plan.days[0].stops.length && !replacementWorked; stop++) {
    await page.locator('.replace-stop').nth(stop).click();
    await page.locator('.replacement-picker').scrollIntoViewIfNeeded();
    await page.screenshot({path:out+`/replacement-${stop}.png`});
    const options = await page.locator('.replacement-picker button:not(.chip-btn)').allTextContents();
    for (const option of options) {
      await page.locator('.replacement-picker').getByRole('button', { name: option, exact: true }).click();
      await page.waitForTimeout(180);
      const changed = await savedTrip(page);
      replacementWorked = changed.snapshot.plan.generatedAt !== original.snapshot.plan.generatedAt;
      replacementAttempts.push({ place: option, accepted: replacementWorked });
      if (replacementWorked) {
        assert.deepEqual(changed.snapshot.plan.days.slice(1), original.snapshot.plan.days.slice(1), 'Replacement reshuffled another day');
        break;
      }
    }
    if (!replacementWorked) await page.getByRole('button',{name:'取消替换',exact:true}).click();
  }
  assert.ok(replacementWorked, 'No feasible replacement could be applied');
  await page.getByRole('button',{name:'撤回刚才调整',exact:true}).click();
  await page.waitForTimeout(180);
  assert.deepEqual((await savedTrip(page)).snapshot.plan.days, original.snapshot.plan.days, 'Undo failed to restore replacement');
  await page.locator('.lock-control').first().click();
  assert.ok(await page.locator('.remove-stop').first().isDisabled(), 'Locked visit can be removed');
  assert.ok(await page.locator('.replace-stop').first().isDisabled(), 'Locked visit can be replaced');
  const lockedStop = (await savedTrip(page)).snapshot.plan.days[0].stops[0];
  await page.getByRole('button',{name:'调整',exact:true}).click();
  await page.getByRole('radio',{name:'充实 愿意多走一点'}).click();
  await page.getByRole('button',{name:'应用调整',exact:true}).click();
  await page.waitForTimeout(180);
  const lockedResult = (await savedTrip(page)).snapshot.plan.days[0].stops.find(s=>s.place.id===lockedStop.place.id);
  assert.ok(lockedResult, 'Locked visit changed day');
  assert.equal(lockedResult.arriveMinute, lockedStop.arriveMinute, 'Locked arrival moved');
  assert.equal(lockedResult.leaveMinute, lockedStop.leaveMinute, 'Locked departure moved');
  await page.getByRole('button',{name:'撤回刚才调整',exact:true}).click();
  await page.getByRole('button',{name:`解锁${lockedStop.place.name}`,exact:true}).click();
  await page.getByRole('radio',{name:/第 1 天/}).focus();
  await page.keyboard.press('ArrowRight');
  assert.equal(await page.getByRole('radio',{name:/第 2 天/}).getAttribute('aria-checked'), 'true');
  await page.keyboard.press('Home');
  await page.getByRole('button',{name:'调整',exact:true}).click();
  await page.getByText('有没有一定想去的地方？',{exact:true}).click();
  await page.getByRole('button',{name:'必去平江路历史街区',exact:true}).click();
  await page.getByRole('button',{name:'应用调整',exact:true}).click();
  await page.getByRole('heading',{name:/一带/}).waitFor();
  await page.waitForTimeout(800);
  const before = await page.evaluate(() => JSON.parse(localStorage.getItem('anytravel-web:current-trip')).trips[0]);
  const remove = page.getByRole('button',{name:/^移除/}).first();
  await remove.click();
  await page.waitForTimeout(800);
  const after = await page.evaluate(() => JSON.parse(localStorage.getItem('anytravel-web:current-trip')).trips[0]);
  assert.deepEqual(after.snapshot.plan.days.slice(1), before.snapshot.plan.days.slice(1), 'Removal reshuffled another day');
  assert.equal(after.snapshot.plan.days[0].stops.length, before.snapshot.plan.days[0].stops.length - 1);
  console.log('EDIT', JSON.stringify({before:before.snapshot.plan.days.map(d=>d.stops.map(s=>s.place.id)), after:after.snapshot.plan.days.map(d=>d.stops.map(s=>s.place.id))}));
  await page.getByRole('button',{name:'撤回刚才调整',exact:true}).click();
  await page.getByRole('button',{name:'铺松一点',exact:true}).click();
  await page.waitForTimeout(800);
  const relaxed = await page.evaluate(() => JSON.parse(localStorage.getItem('anytravel-web:current-trip')).trips[0]);
  if (relaxed.draft.dayCount !== 3) throw Error('Relax changed travel days');
  const view = await page.evaluate(() => ({ width:innerWidth, scrollWidth:document.documentElement.scrollWidth, headings:document.querySelectorAll('.plan-panel h1').length }));
  console.log('LAYOUT',JSON.stringify(view),'ERRORS',JSON.stringify(errors));
  await page.screenshot({path:out+'/desktop-relaxed.png'});
  fs.writeFileSync(out+'/motion-checks.json',JSON.stringify({samples:motionSamples,settledError:motionAligned},null,2));
  const mobile = await browser.newPage({viewport:{width:390,height:844},isMobile:true,hasTouch:true});
  mobile.on('pageerror', e => errors.push(e.message));
  await mobile.goto(base);
  await mobile.getByRole('button',{name:'杭州',exact:true}).click();
  await mobile.getByLabel('出发日期',{exact:true}).fill('2026-10-06');
  await mobile.getByRole('button',{name:'生成我的路线',exact:true}).click();
  await mobile.getByRole('heading',{name:/一带/}).waitFor();
  await mobile.locator('.map-pin').first().waitFor({timeout:30000}); await mobile.locator('[data-map-ready=true]').waitFor({timeout:30000}); await mobile.waitForTimeout(600);
  await mobile.screenshot({path:out+'/mobile-plan.png'});
  await mobile.getByRole('button',{name:'切换面板高度',exact:true}).click();
  await mobile.waitForTimeout(600);
  await mobile.screenshot({path:out+'/mobile-expanded.png'});
  await mobile.emulateMedia({reducedMotion:'reduce'});
  await mobile.getByRole('radio',{name:/第 2 天/}).click();
  const reducedError = await mobile.evaluate(async () => {
    await new Promise(requestAnimationFrame);
    const thumb = document.querySelector('.day-switcher .motion-tab-thumb').getBoundingClientRect();
    const target = document.querySelector('.day-switcher [aria-checked=true]').getBoundingClientRect();
    return Math.abs(thumb.x - target.x);
  });
  assert.ok(reducedError < 0.5, `Reduced motion selection is displaced by ${reducedError}px`);
  await mobile.screenshot({path:out+'/mobile-reduced-motion.png'});
  await mobile.getByRole('button',{name:'切换面板高度',exact:true}).click();
  await mobile.getByRole('button',{name:'切换到深色地图',exact:true}).click();
  await mobile.locator('[data-map-ready=true][data-map-theme=dark]').waitFor({timeout:30000}); await mobile.waitForTimeout(500);
  const darkHeadingColor = await mobile.locator('.plan-panel h1').evaluate(el=>getComputedStyle(el).color);
  assert.equal(darkHeadingColor, 'rgb(237, 246, 243)', 'Dark heading did not inherit the light text token');
  const singlePin = await mobile.locator('.map-pin').first().boundingBox();
  const mobileSheet = await mobile.locator('.mobile-sheet').boundingBox();
  assert.ok(singlePin.y + singlePin.height < mobileSheet.y, 'Single destination marker is hidden behind the sheet');
  await mobile.screenshot({path:out+'/mobile-dark.png'});
  for (const width of [320,375,414,768,1440]) {
    await mobile.setViewportSize({width,height:900});
    await mobile.waitForTimeout(250);
    const overflow = await mobile.evaluate(()=>document.documentElement.scrollWidth > innerWidth);
    if(overflow) throw Error('Horizontal overflow '+width);
  }
  const offline = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  await offline.route('**/*', route => new URL(route.request().url()).origin === new URL(base).origin ? route.continue() : route.abort());
  await offline.goto(base);
  await offline.getByRole('button',{name:'苏州',exact:true}).click();
  await offline.getByRole('button',{name:'生成我的路线',exact:true}).click();
  await offline.locator('.plan-panel h1').waitFor();
  assert.ok((await savedTrip(offline)).snapshot.plan.days.some(d=>d.stops.length), 'Local planning requires a live service');
  await offline.screenshot({path:out+'/service-unavailable.png'});
  const noJS = await browser.newPage({javaScriptEnabled:false});
  await noJS.goto(base);
  assert.match(await noJS.locator('body').innerText(), /请启用后刷新页面/);
  assert.deepEqual(errors, [], 'Unexpected browser errors');
  fs.writeFileSync(out+'/browser-checks.json',JSON.stringify({status:'passed',checkedAt:new Date().toISOString(),errors,desktop:view,replacementAttempts,lockedSlotPreserved:true,localEditsPreserveOtherDays:true,keyboardNavigation:true,reducedMotionError:reducedError,darkHeadingColor,singlePinVisible:true,offlineLocalPlan:true,noJavaScriptNotice:true,relaxedDayCount:relaxed.draft.dayCount,widths:[320,375,390,414,768,1440]},null,2));
  console.log('Browser checks passed; evidence in', out);
  await browser.close();
})().catch(e=>{fs.writeFileSync(out+'/browser-checks.json',JSON.stringify({status:'failed',checkedAt:new Date().toISOString(),error:e.message},null,2));console.error(e);process.exit(1)});
