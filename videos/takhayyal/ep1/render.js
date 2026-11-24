// usage: node render.js preview t1 t2 ...   |  node render.js video out.mp4 duration fps
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
(async () => {
  const [mode, ...args] = process.argv.slice(2);
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1080, height: 1920 } });
  page.on('pageerror', e => console.error('PAGE ERROR', e.message));
  await page.goto('file://' + path.join(__dirname, 'scene.html'));
  await page.evaluate(() => window.ready);
  const grab = t => page.evaluate(t => { render(t); return document.getElementById('c').toDataURL('image/jpeg', 0.92); }, t);
  if (mode === 'preview') {
    fs.mkdirSync(path.join(__dirname, 'prev'), { recursive: true });
    for (const t of args) {
      const d = await grab(parseFloat(t));
      fs.writeFileSync(path.join(__dirname, 'prev', `f_${t}.jpg`), Buffer.from(d.split(',')[1], 'base64'));
    }
  } else {
    const [out, dur, fps] = [args[0], parseFloat(args[1]), parseInt(args[2] || '30')];
    const ff = spawn('ffmpeg', ['-y', '-f', 'image2pipe', '-framerate', String(fps), '-c:v', 'mjpeg', '-i', '-',
      '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-preset', 'medium', '-crf', '18', out], { stdio: ['pipe', 'ignore', 'inherit'] });
    const n = Math.round(dur * fps);
    for (let i = 0; i < n; i++) {
      const d = await grab(i / fps);
      const buf = Buffer.from(d.split(',')[1], 'base64');
      if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
      if (i % 150 === 0) console.log(`frame ${i}/${n}`);
    }
    ff.stdin.end();
    await new Promise(r => ff.on('close', r));
  }
  await browser.close();
})();
