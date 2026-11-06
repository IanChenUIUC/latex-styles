// Typesets a JSON list of formulas with MathJax and writes each one's size in em.

const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, 'node_modules/mathjax');
global.MathJax = {
  loader: { paths: { mathjax: root }, load: ['input/tex', 'output/svg', 'adaptors/liteDOM'], require },
  output: { font: 'mathjax-newcm' },
  startup: { typeset: false },
};
require(path.join(root, 'startup.js'));

(async () => {
  await MathJax.startup.promise;
  const adaptor = MathJax.startup.adaptor;
  const out = [];
  for (const tex of JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))) {
    const mml = await MathJax.tex2mmlPromise(tex, { display: true });
    const svg = adaptor.outerHTML(await MathJax.tex2svgPromise(tex, { display: true }));
    const [, , , w, h] = svg.match(/viewBox="([-\d.]+) ([-\d.]+) ([-\d.]+) ([-\d.]+)"/);
    out.push({ w: w / 1000, h: h / 1000, error: /<merror|<mtext[^>]*mathcolor="red"/.test(mml) });
  }
  fs.writeFileSync(process.argv[3], JSON.stringify(out));
})().catch((error) => { console.error(error); process.exit(1); });
