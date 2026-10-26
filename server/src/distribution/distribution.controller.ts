import { Controller, Get, Res } from '@nestjs/common';
import { Response } from 'express';
import * as path from 'path';
import * as fs from 'fs';

@Controller('download')
export class DistributionController {
  // On the home server the .ipa is uploaded to ~/our-chat/downloads (mounted at IPA_PATH) by
  // scripts/publish-ipa.sh; the other paths are for running the server on the Mac itself.
  private readonly ipaPaths = [
    process.env.IPA_PATH,
    path.resolve(process.cwd(), '../dist/OurChat.ipa'),
    path.resolve(process.cwd(), 'dist/OurChat.ipa'),
  ].filter((p): p is string => !!p);

  private resolveIpa(): string | null {
    return this.ipaPaths.find((p) => fs.existsSync(p)) ?? null;
  }

  @Get()
  getDownloadPage(@Res() res: Response) {
    const hasIpa = this.resolveIpa() !== null;

    const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Our Chat — Install on iOS</title>
  <style>
    :root {
      --bg: #0d1117;
      --card-bg: #161b22;
      --accent: #2AABEE;
      --accent-hover: #229ED9;
      --text-primary: #f0f6fc;
      --text-secondary: #8b949e;
      --border: #30363d;
      --success: #238636;
      --font: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background-color: var(--bg);
      color: var(--text-primary);
      font-family: var(--font);
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      padding: 20px;
    }
    .card {
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: 16px;
      max-width: 520px;
      width: 100%;
      padding: 32px 24px;
      text-align: center;
      box-shadow: 0 12px 32px rgba(0,0,0,0.5);
    }
    .icon {
      width: 80px;
      height: 80px;
      border-radius: 20px;
      margin-bottom: 16px;
      box-shadow: 0 8px 24px rgba(42, 171, 238, 0.3);
    }
    h1 { font-size: 24px; font-weight: 700; margin-bottom: 8px; }
    p.subtitle { color: var(--text-secondary); font-size: 14px; margin-bottom: 24px; line-height: 1.5; }
    .btn {
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 10px;
      width: 100%;
      padding: 14px;
      background: var(--accent);
      color: #fff;
      text-decoration: none;
      font-weight: 600;
      border-radius: 12px;
      font-size: 16px;
      border: none;
      cursor: pointer;
      transition: background 0.2s;
      margin-bottom: 16px;
    }
    .btn:hover { background: var(--accent-hover); }
    .btn.secondary {
      background: #21262d;
      color: var(--text-primary);
      border: 1px solid var(--border);
    }
    .btn.secondary:hover { background: #30363d; }
    .guide-box {
      text-align: left;
      background: #0d1117;
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 16px;
      margin-top: 20px;
    }
    .guide-box h3 { font-size: 15px; margin-bottom: 12px; color: var(--accent); display: flex; align-items: center; gap: 6px; }
    .guide-box ol { padding-left: 20px; color: var(--text-secondary); font-size: 13px; line-height: 1.7; }
    .guide-box ol li strong { color: var(--text-primary); }
    .badge {
      display: inline-block;
      padding: 4px 10px;
      background: rgba(35, 134, 54, 0.2);
      color: #3fb950;
      border-radius: 20px;
      font-size: 12px;
      font-weight: 600;
      margin-bottom: 12px;
    }
    .code-tag {
      background: #21262d;
      color: #58a6ff;
      padding: 2px 6px;
      border-radius: 4px;
      font-family: monospace;
      font-size: 12px;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">E2EE Private Team Communication</div>
    <div style="display:flex; justify-content:center;">
      <div style="width:72px; height:72px; background:linear-gradient(135deg, #2AABEE 0%, #229ED9 100%); border-radius:20px; display:flex; align-items:center; justify-content:center; font-size:36px; margin-bottom:16px;">💬</div>
    </div>
    <h1>Install Our Chat</h1>
    <p class="subtitle">Secure, native iOS app for private messaging and HD calls across any network.</p>

    ${hasIpa ? '' : '<p class="subtitle" style="color:#f85149">The app file is not uploaded yet. On the host Mac run: ./scripts/install_device.sh --package-ipa</p>'}
    <a href="/api/v1/download/OurChat.ipa" class="btn">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96zM17 13l-5 5-5-5h3V9h4v4h3z"/></svg>
      Download OurChat.ipa
    </a>

    <div class="guide-box">
      <h3>📲 Install with your own Apple ID (free)</h3>
      <ol>
        <li>On a Mac or Windows PC, install <strong>Sideloadly</strong> (free, sideloadly.io). On Windows, also install iTunes and iCloud from apple.com (not the Microsoft Store versions).</li>
        <li>Download <strong class="code-tag">OurChat.ipa</strong> above to that computer.</li>
        <li>Plug in your iPhone, unlock it and tap <strong>Trust</strong>.</li>
        <li>Drag <strong class="code-tag">OurChat.ipa</strong> into Sideloadly, enter <strong>your own Apple ID</strong> and click <strong>Start</strong>.</li>
        <li>If it says the App ID is not available: open <strong>Advanced options</strong>, change the <strong>Bundle ID</strong> (add your name, e.g. <span class="code-tag">com.minitelegram.ios.dara</span>) and press Start again.</li>
        <li>On the iPhone: <strong>Settings &rarr; General &rarr; VPN &amp; Device Management</strong> &rarr; your Apple ID &rarr; <strong>Trust</strong>.</li>
        <li>iOS 16 or later: <strong>Settings &rarr; Privacy &amp; Security &rarr; Developer Mode</strong> &rarr; On, restart, then tap Turn On.</li>
        <li>Open Our Chat. With a free Apple ID the app stops opening after <strong>7 days</strong>: repeat step 4 to renew it (your chats are kept).</li>
      </ol>
    </div>

    <div class="guide-box" style="margin-top: 14px;">
      <h3>⚡ Connected via USB/Wi-Fi to Host Mac?</h3>
      <p style="color:var(--text-secondary); font-size:13px; line-height:1.6;">
        Plug your iPhone into the host Mac and run:
        <br>
        <span class="code-tag" style="display:inline-block; margin-top:6px; padding:6px 10px;">./scripts/install_device.sh</span>
        <br>
        This compiles and installs directly onto the device automatically.
      </p>
    </div>
  </div>
</body>
</html>`;

    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.send(html);
  }

  @Get('OurChat.ipa')
  downloadIpa(@Res() res: Response) {
    const file = this.resolveIpa();
    if (!file) {
      res.status(404).send('OurChat.ipa has not been generated yet. Please run ./scripts/install_device.sh --package-ipa on the host Mac.');
      return;
    }

    res.download(file, 'OurChat.ipa', (err) => {
      if (err) {
        if (!res.headersSent) {
          res.status(500).send('Failed to transfer IPA file.');
        }
      }
    });
  }
}
