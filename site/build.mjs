#!/usr/bin/env node
// bloodglucosebuddy.tanookistudios.com - a small static site, built from this folder into site/dist.
//
//   node site/build.mjs                 build
//   node site/build.mjs --deploy        build, then deploy to the Cloudflare Pages project "bloodglucosebuddy-site"
//
// Versions come from site/versions.json (newest first); each one's zip is a GitHub release asset on
// TanookiStudios/BloodGlucoseBuddy, tag v<version>, made by scripts/release-mac.sh.
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, "..");
const out = path.join(here, "dist");
const NAME = "Blood Glucose Buddy";
const SITE = "https://bloodglucosebuddy.tanookistudios.com";
const REPO = "https://github.com/TanookiStudios/BloodGlucoseBuddy";
const TIP = "https://tanookistudios.com/SupportMe";
const VERSIONS = JSON.parse(fs.readFileSync(path.join(here, "versions.json"), "utf8"));
const LATEST = VERSIONS[0];
const appVersion = fs.readFileSync(path.join(root, "mac", "project.yml"), "utf8").match(/MARKETING_VERSION: "([^"]+)"/)[1];
if (appVersion !== LATEST.version) throw new Error(`site/versions.json starts at ${LATEST.version} but mac/project.yml is ${appVersion} - add the new version's notes first`);
const zipOf = (v) => `${REPO}/releases/download/v${v}/BloodGlucoseBuddy-${v}-mac.zip`;
const fmtDate = (d) => new Date(`${d}T12:00:00Z`).toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric", timeZone: "UTC" });
const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const CSS = fs.readFileSync(path.join(here, "style.css"), "utf8");

const NAV = [["index.html", "Home"], ["how-it-works.html", "How It Works"], ["download.html", "Download"], ["privacy.html", "Privacy"], ["about-maddie.html", "About Maddie"]];
const href = (f) => (f === "index.html" ? "/" : `/${f.replace(".html", "")}`);
const SIG = fs.readFileSync(path.join(root, "assets", "signature.svg"), "utf8").replace(/<\?xml[^>]*>/, "").replace("<svg", '<svg role="img" aria-label="Signed, Maddie" class="sig"');

const DISCLAIMER = `Not a medical device. Never make treatment decisions from ${NAME} - use your Dexcom app or receiver. It reads Dexcom's unofficial Share feed, which can stop working without notice. ${NAME} is not affiliated with or endorsed by Dexcom or Discord.`;

// A drawing of a Discord profile card, built from the same pictures the app uploads to Discord.
const card = ({ img, details, state, elapsed, label }) => `<figure>
<div class="dc" role="img" aria-label="${esc(label)}">
  <div class="who"><span class="av"></span><span class="nm">You</span></div>
  <p class="lbl">Watching</p>
  <div class="act"><img src="/shots/${img}.png" alt="" width="64" height="64">
    <div><div class="t">Blood Glucose</div><div class="d">${esc(details)}</div>${state ? `<div class="d">${esc(state)}</div>` : ""}<div class="e">${esc(elapsed)}</div></div>
  </div>
</div>
<figcaption>${esc(label)}</figcaption></figure>`;

function page({ file, title, desc, body, robots = "index, follow, max-image-preview:large" }) {
  const url = `${SITE}${href(file)}`;
  const app = { "@context": "https://schema.org", "@type": "SoftwareApplication", name: NAME, applicationCategory: "UtilitiesApplication", operatingSystem: "macOS 15 or later", softwareVersion: LATEST.version, offers: { "@type": "Offer", price: "0", priceCurrency: "USD" }, url: SITE, author: { "@type": "Person", name: "Maddie" }, publisher: { "@type": "Organization", name: "Tanooki Studios", url: "https://tanookistudios.com" } };
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(desc)}">
${robots === "noindex" ? "" : `<link rel="canonical" href="${url}">`}
<meta name="robots" content="${robots}">
<link rel="icon" type="image/png" sizes="32x32" href="/favicon-32.png"><link rel="apple-touch-icon" href="/apple-touch-icon.png">
<meta property="og:title" content="${esc(title)}"><meta property="og:description" content="${esc(desc)}"><meta property="og:type" content="website"><meta property="og:url" content="${url}"><meta property="og:image" content="${SITE}/icon-512.png"><meta property="og:site_name" content="${NAME}">
<meta name="twitter:card" content="summary"><meta name="twitter:title" content="${esc(title)}"><meta name="twitter:description" content="${esc(desc)}"><meta name="twitter:image" content="${SITE}/icon-512.png">
<script type="application/ld+json">${JSON.stringify(app).replace(/</g, "\\u003c")}</script>
<style>${CSS}</style>
</head>
<body>
<a class="skip" href="#main">Skip To Content</a>
<header class="top"><div class="wrap">
  <a class="brand" href="/"><img src="/icon-512.png" alt="" width="30" height="30">${NAME}</a>
  <nav class="main" aria-label="Main">${NAV.map(([f, l]) => `<a href="${href(f)}"${f === file ? ' aria-current="page"' : ""}>${l}</a>`).join("")}</nav>
</div></header>
<main id="main"><div class="wrap">
${body}
</div></main>
<footer><div class="wrap">
  <span>${NAME} is free and open source (MIT). Made by Maddie at <a href="https://tanookistudios.com">Tanooki Studios</a>.</span>
  <span><a href="${REPO}">Source Code</a> · <a href="/privacy">Privacy</a> · <a href="${TIP}">Support My Work</a> · <a href="https://tanookistudios.com/contact">Contact</a></span>
</div></footer>
</body>
</html>
`;
}

const pages = {};

pages["index.html"] = page({
  file: "index.html",
  title: `${NAME} - Your Dexcom Reading on Your Discord Profile`,
  desc: "Free Mac app that shows your live Dexcom blood glucose and trend arrow on your Discord profile, or just a green, yellow or red dot if you'd rather keep the number private. Open source.",
  body: `
<section class="hero">
  <div>
    <p class="eyebrow">Free Mac App · v${LATEST.version}</p>
    <h1>Your blood sugar, on your Discord profile.</h1>
    <p class="lede">${NAME} reads your Dexcom every five minutes and shows it under your name in Discord, trend arrow and all. It sits quietly in your Mac's menu bar and you never have to think about it again.</p>
    <div class="btns"><a class="btn pink" href="/download">Download for Mac</a><a class="btn" href="/how-it-works">How It Works</a></div>
    <p class="small">macOS 15 or later, plus the Discord desktop app. Windows version on the way.</p>
  </div>
  ${card({ img: "up_45", details: "112 mg/dL ↗", state: "Rising slowly", elapsed: "02:14 elapsed", label: "Number mode: your reading, trend arrow and how old the reading is." })}
</section>

<h2>Show As Much As You Like</h2>
<div class="cards2">
  ${card({ img: "flat", details: "6.2 mmol/L →", state: "Steady", elapsed: "00:41 elapsed", label: "Number mode, in mmol/L. Switch units from the menu bar." })}
  ${card({ img: "dot_green", details: "In range", state: "", elapsed: "03:02 elapsed", label: "Colored dot mode: green, yellow or red, and no number at all." })}
</div>

<h2>Why You'll Like It</h2>
<div class="grid3">
  <div class="card"><h3>Live, Not An Hour Late</h3><p>Dexcom's official developer feed runs an hour behind. ${NAME} uses Share, the same live feed the Dexcom Follow app uses, so what your friends see is what your phone sees.</p></div>
  <div class="card"><h3>Your Number, Your Call</h3><p>Show the number, or switch to a colored dot that only says In range, High or Low. You pick the high and low lines.</p></div>
  <div class="card"><h3>Never A Stale Number</h3><p>If a reading is more than fifteen minutes old, it says <em>No reading</em> instead. Nobody sees an old number as if it were now.</p></div>
  <div class="card"><h3>In Your Menu Bar Too</h3><p>Your current number and arrow sit at the top of your screen. Click it for settings. It starts by itself when you log in.</p></div>
  <div class="card"><h3>Password Stays Put</h3><p>Your Dexcom password lives in your Mac's Keychain and only ever goes to Dexcom. No account, no server, no analytics.</p></div>
  <div class="card"><h3>Open Source</h3><p>Every line is <a href="${REPO}">on GitHub</a> under the MIT license, including the part that touches your Dexcom login.</p></div>
</div>

<p class="warn">${DISCLAIMER}</p>

<h2>Free, And Staying Free</h2>
<p class="prose">No paid tier, no ads, nothing held back. ${NAME} is made by <a href="/about-maddie">Maddie</a>, an autistic developer who builds small apps for fun and for a living. If it made you smile, you can <a href="${TIP}">support her work</a>.</p>
<div class="btns"><a class="btn pink" href="/download">Download ${NAME} ${LATEST.version}</a></div>
`,
});

pages["how-it-works.html"] = page({
  file: "how-it-works.html",
  title: `How ${NAME} Works - Setup in Five Minutes`,
  desc: `Install ${NAME}, sign in with your Dexcom login, and turn on one Discord setting. Step by step, with answers to common questions.`,
  body: `
<div class="prose">
<p class="eyebrow">Setup</p>
<h1>How It Works</h1>
<p class="lede">Three things, about five minutes, once.</p>

<h2>1. Turn On Dexcom Share</h2>
<p>${NAME} reads the same live feed your followers see, so Share has to be on. If someone already follows you in the Dexcom Follow app, it's on and you can skip this.</p>
<ol class="how">
  <li>Open the Dexcom app on your phone.</li>
  <li>Tap the Share icon - it looks like two little people.</li>
  <li>Turn Share on and invite one follower. Any email address of your own will do; nobody has to accept the invite.</li>
</ol>

<h2>2. Install And Sign In</h2>
<ol class="how">
  <li><a href="/download">Download the latest version</a> and double-click the zip to unzip it.</li>
  <li>Drag <strong>${NAME}</strong> into your Applications folder and open it.</li>
  <li>A sign-in window opens. Use your own Dexcom login - the one you use in the Dexcom app - not a follower's. Phone numbers need a plus and your country code, like <code>+15551234567</code>.</li>
  <li>Pick your region and press <strong>Sign In</strong>. The drop in your menu bar turns into your number.</li>
</ol>
<p class="note">Email or phone not accepted? Lots of Dexcom accounts only work with their account ID. Press <strong>Find My Account ID</strong> in the sign-in window, sign in to Dexcom on the page that opens, and the app fills it in for you. Then type your password once more.</p>

<h2>3. Let Discord Show It</h2>
<p>Discord hides activity from apps until you say otherwise.</p>
<ol class="how">
  <li>In the Discord desktop app, click the gear at the bottom left to open User Settings.</li>
  <li>Under Activity Settings, choose <strong>Activity Privacy</strong>.</li>
  <li>Turn on <strong>Share your detected activities with others</strong>.</li>
</ol>
<p>Click your own picture in Discord and you'll see <em>Watching Blood Glucose</em> with your reading.</p>

<h2>Common Questions</h2>
<details class="faq"><summary>Who can see my reading?</summary><p>Anyone who can see your Discord profile - friends and people in every server you're in. To hide it from one server, right-click that server in Discord, choose Privacy Settings, and turn off Activity Status. Or switch to colored dot mode so nobody sees a number at all.</p></details>
<details class="faq"><summary>Why doesn't it work on my phone?</summary><p>Discord only lets apps set your status from the same computer as the Discord desktop app. There's no way for a phone app to do it without breaking Discord's rules, which can get accounts banned.</p></details>
<details class="faq"><summary>It says No reading.</summary><p>Your latest reading is more than fifteen minutes old - your sensor might be warming up, or your phone lost signal. It picks back up on its own as soon as a new reading arrives.</p></details>
<details class="faq"><summary>Dexcom says my account is locked.</summary><p>Dexcom locks accounts for a while after several wrong passwords. ${NAME} stops trying the moment a password is turned down, so it won't make that worse. Wait about half an hour, then open Settings from the menu, sign out, and sign back in.</p></details>
<details class="faq"><summary>Does it work with Libre or other sensors?</summary><p>Not right now - it only reads Dexcom Share.</p></details>
<details class="faq"><summary>Can I trust it for my insulin?</summary><p>No. ${DISCLAIMER}</p></details>
<details class="faq"><summary>How do I update to a new version?</summary><p>Download the new version from the <a href="/download">Download page</a> and drag it into Applications, replacing the old one. You stay signed in.</p></details>
</div>
`,
});

pages["download.html"] = page({
  file: "download.html",
  title: `Download ${NAME} for Mac`,
  desc: `Download ${NAME} ${LATEST.version} for Mac. Free and open source, signed and notarized by Apple. Every version, with what changed.`,
  body: `
<div class="prose">
<p class="eyebrow">Download</p>
<h1>Download ${NAME}</h1>
<p class="lede">Free, for Mac. Signed and notarized by Apple, so it opens without warnings.</p>
<div class="btns"><a class="btn pink" href="${zipOf(LATEST.version)}">Download ${LATEST.version} for Mac</a><a class="btn" href="/how-it-works">Setup Steps</a></div>
<p class="small">Needs macOS 15 or later and the Discord desktop app. Released ${fmtDate(LATEST.date)}. A Windows version is on the way.</p>
<h2>Every Version</h2>
${VERSIONS.map((v, i) => `<div class="version"><div><strong>${v.version}</strong>${i === 0 ? '<span class="badge">Latest</span>' : ""}<div class="small">${fmtDate(v.date)}</div><div class="small"><a href="${zipOf(v.version)}">Download zip</a></div></div><ul>${v.notes.map((n) => `<li>${esc(n)}</li>`).join("")}</ul></div>`).join("\n")}
<p class="small">Prefer to build it yourself? The <a href="${REPO}">source code</a> is on GitHub.</p>
</div>
`,
});

pages["privacy.html"] = page({
  file: "privacy.html",
  title: `Privacy - ${NAME}`,
  desc: `${NAME} has no account, no server and no analytics. Your Dexcom password goes only to Dexcom, and your reading goes only to the Discord app on your own Mac.`,
  body: `
<div class="prose">
<p class="eyebrow">Privacy</p>
<h1>Privacy Policy</h1>
<p class="muted">Last updated ${fmtDate("2026-10-09")}.</p>
<h2>The Short Version</h2>
<p>${NAME} has no account, no server of its own, and no analytics. Tanooki Studios never receives your login, your readings or anything else from the app.</p>
<h2>Your Dexcom Login</h2>
<p>Your Dexcom username (or account ID) and password are stored in your Mac's Keychain. They are sent only to Dexcom's Share service, over an encrypted connection, to fetch your latest reading. If you use <em>Find My Account ID</em>, Dexcom's own sign-in page opens inside the app; the app only reads the page address to pick up your account ID, and forgets that sign-in when the window closes.</p>
<h2>Your Reading</h2>
<p>Your latest reading and trend are handed to the Discord desktop app on the same Mac, which shows them on your profile. From there, who sees it is up to Discord and your Discord privacy settings - see <a href="https://discord.com/privacy">Discord's privacy policy</a>. The app keeps no history; it only remembers the latest reading while it's running.</p>
<h2>Signing Out</h2>
<p>Choose Sign Out in Settings and your password is deleted from the Keychain and your Discord status is cleared.</p>
<h2>Third Parties</h2>
<p>Dexcom, to read your glucose, and Discord, to show it. Nothing is sold, shared or used for advertising, because nothing is collected in the first place.</p>
<h2>Medical</h2>
<p>${DISCLAIMER}</p>
<h2>Questions</h2>
<p>Use the <a href="https://tanookistudios.com/contact">contact page</a>.</p>
</div>
`,
});

pages["about-maddie.html"] = page({
  file: "about-maddie.html",
  title: `About Maddie - ${NAME}`,
  desc: "Maddie is an autistic developer who makes small tools that fix one specific irritation properly, plus apps for PC, Mac, phones and tablets.",
  body: `
<div class="prose">
<p class="eyebrow">The Person Behind It</p>
<h1>About Maddie</h1>
<p>I wear a Dexcom and I'm on Discord most of the day, and one afternoon I had a silly idea: what if my blood sugar just showed up under my name? It turned out to be possible, so I built it. It's free, it's for fun, and I hope it makes you smile.</p>
<p>I'm Maddie, I'm autistic, and I often make small tools that fix one specific irritation properly — the sort of thing that's too small for a company to bother with and too annoying to keep putting up with.</p>
<p>I also develop apps for PC, Mac, mobiles, and tablets. I generally develop apps that:</p>
<ol class="how"><li>Help me with a problem that I have.</li><li>Will help others.</li><li>Bring a little bit of good to the world.</li></ol>
<p>This is also my income. Due to my autism, I don't do well with most typical office jobs. In fact, I tend to really struggle. So with the support of my wife, I decided to invest in myself, and create my own apps full-time.</p>
<p>See everything else I make at <a href="https://tanookistudios.com">Tanooki Studios</a>, or <a href="${TIP}">support my work</a>.</p>
${SIG}
</div>
`,
});

// ---- write
fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(path.join(out, "shots"), { recursive: true });
for (const [f, html] of Object.entries(pages)) fs.writeFileSync(path.join(out, f), html);
fs.writeFileSync(path.join(out, "404.html"), page({ file: "404.html", robots: "noindex", title: `Page Not Found - ${NAME}`, desc: "That page isn't here.", body: `<p class="eyebrow">404</p><h1>Page Not Found.</h1><p class="lede">That page isn't here.</p><div class="btns"><a class="btn pink" href="/">Home</a><a class="btn" href="/download">Download ${NAME}</a></div>` }));
for (const f of ["icon-512.png", "apple-touch-icon.png", "favicon-32.png"]) fs.copyFileSync(path.join(here, f), path.join(out, f));
for (const f of fs.readdirSync(path.join(here, "shots"))) fs.copyFileSync(path.join(here, "shots", f), path.join(out, "shots", f));
const today = new Date().toISOString().slice(0, 10);
fs.writeFileSync(path.join(out, "sitemap.xml"), `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${Object.keys(pages).map((f) => `  <url><loc>${SITE}${href(f)}</loc><lastmod>${f === "download.html" ? LATEST.date : today}</lastmod></url>`).join("\n")}\n</urlset>\n`);
fs.writeFileSync(path.join(out, "robots.txt"), `User-agent: *\nAllow: /\nSitemap: ${SITE}/sitemap.xml\n`);
fs.writeFileSync(path.join(out, "_headers"), "/*\n  X-Content-Type-Options: nosniff\n  Referrer-Policy: strict-origin-when-cross-origin\n  X-Frame-Options: DENY\n/shots/*\n  Cache-Control: public, max-age=604800\n");
console.log(`built ${Object.keys(pages).length} pages + 404 for ${NAME} ${LATEST.version} -> ${out}`);

if (process.argv.includes("--deploy")) execFileSync("npx", ["--yes", "wrangler", "pages", "deploy", out, "--project-name", "bloodglucosebuddy-site", "--commit-dirty=true"], { stdio: "inherit", cwd: here }); // cwd: site/, so site/functions deploys too
