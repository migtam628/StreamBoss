// The page the installer shows in the browser (served by ui.dart). One file, no outside requests.
const installerPage = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>StreamBoss for Roku</title>
<style>
:root{--bg:#0e1116;--panel:#171c24;--line:#2a313c;--ink:#eef1f5;--dim:#9aa4b2;--accent:#7c5cff;--accent-ink:#fff;--ok:#2fbf71;--bad:#ff6b6b;color-scheme:dark}
@media (prefers-color-scheme:light){:root{--bg:#f4f5f8;--panel:#fff;--line:#d9dde4;--ink:#171b22;--dim:#5b6573;--accent:#5b3df5;--ok:#168a4f;--bad:#c62828;color-scheme:light}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:640px;margin:0 auto;padding:28px 16px 64px}
h1{font-size:26px;margin:0 0 4px}
.sub{color:var(--dim);margin:0 0 24px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:18px;margin:0 0 14px}
.card[hidden]{display:none}
.card h2{font-size:17px;margin:0 0 10px;display:flex;gap:10px;align-items:center}
.num{display:inline-grid;place-items:center;width:26px;height:26px;border-radius:50%;background:var(--accent);color:var(--accent-ink);font-size:14px;flex:none}
.num.done{background:var(--ok)}
button{font:inherit;border:0;border-radius:10px;padding:10px 16px;background:var(--accent);color:var(--accent-ink);cursor:pointer}
button.ghost{background:transparent;color:var(--ink);border:1px solid var(--line)}
button:disabled{opacity:.5;cursor:default}
button:focus-visible,input:focus-visible{outline:3px solid var(--accent);outline-offset:2px}
input{font:inherit;width:100%;padding:10px 12px;border-radius:10px;border:1px solid var(--line);background:var(--bg);color:var(--ink)}
.row{display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin-top:12px}
.row>input{flex:1;min-width:180px}
.list{display:grid;gap:8px;margin:8px 0 0}
.dev{display:flex;gap:10px;align-items:center;width:100%;text-align:left;background:var(--bg);color:var(--ink);border:1px solid var(--line);padding:12px 14px}
.dev[aria-pressed=true]{border-color:var(--accent);box-shadow:0 0 0 2px var(--accent) inset}
.dev small{color:var(--dim);display:block}
.muted{color:var(--dim);margin:6px 0 0}
.chip{display:inline-block;border-radius:999px;padding:2px 10px;font-size:14px;border:1px solid var(--line)}
.chip.ok{color:var(--ok);border-color:var(--ok)}
.chip.bad{color:var(--bad);border-color:var(--bad)}
ol{padding-left:20px;margin:8px 0}
li{margin:4px 0}
code,kbd{font:14px ui-monospace,Menlo,Consolas,monospace;background:var(--bg);border:1px solid var(--line);border-radius:6px;padding:1px 6px}
.steps{list-style:none;padding:0;margin:12px 0 0}
.steps li{display:flex;gap:10px;align-items:flex-start;margin:8px 0}
.ic{width:22px;height:22px;flex:none;display:grid;place-items:center;border-radius:50%;font-size:13px;border:2px solid var(--line);color:var(--dim)}
.ic.run{border-color:var(--accent);border-top-color:transparent;animation:spin 1s linear infinite}
.ic.done{background:var(--ok);border-color:var(--ok);color:#fff}
.ic.fail{background:var(--bad);border-color:var(--bad);color:#fff}
.note{display:block;color:var(--dim);font-size:14px;overflow-wrap:anywhere}
@keyframes spin{to{transform:rotate(360deg)}}
@media (prefers-reduced-motion:reduce){.ic.run{animation:none}}
.result{border-radius:12px;padding:14px;margin-top:14px;border:1px solid var(--line)}
.result.ok{border-color:var(--ok)}
.result.bad{border-color:var(--bad)}
.result h3{margin:0 0 6px;font-size:18px}
footer{color:var(--dim);font-size:14px;margin-top:20px;display:flex;justify-content:space-between;gap:12px;flex-wrap:wrap}
</style>
</head>
<body>
<main>
  <h1>StreamBoss for Roku</h1>
  <p class="sub">This puts the StreamBoss channel on your Roku. It takes about a minute. Your computer and the Roku must be on the same network.</p>

  <section class="card" id="s1">
    <h2><span class="num" id="n1">1</span> Pick your Roku</h2>
    <div id="scanState" class="muted">Looking for Rokus on your network...</div>
    <div class="list" id="devices"></div>
    <div class="row">
      <button class="ghost" id="rescan" type="button">Search again</button>
    </div>
    <div class="row">
      <input id="addr" inputmode="decimal" autocomplete="off" placeholder="or type its address, like 192.168.1.40" aria-label="Roku address">
      <button class="ghost" id="useAddr" type="button">Use this address</button>
    </div>
    <p class="muted">The address is on the Roku: Settings &gt; Network &gt; About.</p>
  </section>

  <section class="card" id="s2" hidden>
    <h2><span class="num" id="n2">2</span> Turn on developer mode (once)</h2>
    <p id="devState" class="muted"></p>
    <div id="devHelp" hidden>
      <p>Your Roku is not set up to take apps from a computer yet. This is done once, on the TV.</p>
      <div class="row">
        <button id="openDev" type="button">Open Developer Settings on my TV</button>
        <button class="ghost" id="recheck" type="button">Check again</button>
      </div>
      <p class="muted" id="devMsg"></p>
      <p>If that does not work, on the Roku remote press: <kbd>Home</kbd> x3, <kbd>Up</kbd> x2, then <kbd>Right</kbd> <kbd>Left</kbd> <kbd>Right</kbd> <kbd>Left</kbd> <kbd>Right</kbd>.</p>
      <p>Then on the TV:</p>
      <ol>
        <li>Choose <b>Enable installer and restart</b>.</li>
        <li>Accept the licence.</li>
        <li><b>Choose a password</b> and remember it. You type it in the next step.</li>
        <li>Wait for the Roku to restart, then press <b>Check again</b>.</li>
      </ol>
    </div>
  </section>

  <section class="card" id="s3" hidden>
    <h2><span class="num" id="n3">3</span> Install</h2>
    <div id="pwBox">
      <label for="pw">The developer password you chose on the TV</label>
      <div class="row">
        <input id="pw" type="password" autocomplete="off" aria-label="Developer password">
        <button class="ghost" id="showPw" type="button" aria-pressed="false">Show</button>
      </div>
      <div class="row"><button id="install" type="button">Install StreamBoss</button></div>
    </div>
    <ul class="steps" id="steps" aria-live="polite"></ul>
    <div class="result" id="result" hidden></div>
  </section>

  <footer>
    <span>Closing this tab closes the installer.</span>
    <button class="ghost" id="quit" type="button">Close the installer</button>
  </footer>
</main>
<script>
(function(){
  var T = new URLSearchParams(location.search).get('t') || '';
  var $ = function(id){ return document.getElementById(id); };
  var host = '', pollTimer = null, busy = false;

  function api(path, body){
    return fetch(path, {
      method: body === undefined ? 'GET' : 'POST',
      headers: {'x-token': T, 'content-type': 'application/json'},
      body: body === undefined ? undefined : JSON.stringify(body)
    }).then(function(r){
      return r.json().then(function(j){ if(!r.ok) throw new Error(j.error || 'Something went wrong.'); return j; });
    });
  }
  function clear(el){ while(el.firstChild) el.removeChild(el.firstChild); }
  function el(tag, cls, text){ var e = document.createElement(tag); if(cls) e.className = cls; if(text !== undefined) e.textContent = text; return e; }

  // Keep-alive: the program ends when this page has been closed for a while.
  setInterval(function(){ api('/api/ping').catch(function(){}); }, 5000);
  api('/api/ping').catch(function(){});

  function scan(){
    $('scanState').textContent = 'Looking for Rokus on your network...';
    clear($('devices'));
    $('rescan').disabled = true;
    api('/api/scan', {}).then(function(r){
      var list = r.devices || [];
      $('scanState').textContent = list.length ? (list.length === 1 ? 'Found one Roku.' : 'Found ' + list.length + ' Rokus. Pick one.') : 'No Roku found. Type its address below.';
      list.forEach(function(d){
        var b = el('button', 'dev'); b.type = 'button'; b.setAttribute('aria-pressed', 'false');
        var t = el('span'); t.appendChild(document.createTextNode(d.label));
        b.appendChild(t);
        b.onclick = function(){ choose(d.host, b); };
        $('devices').appendChild(b);
      });
      if(list.length === 1 && !host) $('devices').firstChild.click();
    }).catch(function(e){ $('scanState').textContent = e.message; })
      .then(function(){ $('rescan').disabled = false; });
  }

  function choose(h, btn){
    host = h;
    Array.prototype.forEach.call($('devices').children, function(c){ c.setAttribute('aria-pressed', c === btn ? 'true' : 'false'); });
    check();
  }

  function check(){
    $('s2').hidden = false; $('devMsg').textContent = '';
    $('devState').textContent = 'Checking ' + host + '...';
    $('devHelp').hidden = true; $('s3').hidden = true;
    api('/api/check', {host: host}).then(function(r){
      if(!r.reachable){
        $('devState').textContent = '';
        $('devHelp').hidden = true;
        var chip = el('span', 'chip bad', 'Not found'); clear($('devState')); $('devState').appendChild(chip);
        $('devState').appendChild(document.createTextNode(' Nothing answered at ' + host + '. Check the address, and that the Roku is on and on this network.'));
        return;
      }
      clear($('devState'));
      if(r.installerUp){
        $('devState').appendChild(el('span', 'chip ok', 'Developer mode is on'));
        $('n2').className = 'num done';
        $('devHelp').hidden = true;
        $('s3').hidden = false;
        $('pw').focus();
      } else {
        $('devState').appendChild(el('span', 'chip bad', 'Developer mode is off'));
        $('n2').className = 'num';
        $('devHelp').hidden = false;
      }
    }).catch(function(e){ $('devState').textContent = e.message; });
  }

  $('rescan').onclick = scan;
  $('useAddr').onclick = function(){
    var v = $('addr').value.trim(); if(!v) return;
    Array.prototype.forEach.call($('devices').children, function(c){ c.setAttribute('aria-pressed', 'false'); });
    host = v; check();
  };
  $('addr').onkeydown = function(e){ if(e.key === 'Enter') $('useAddr').click(); };
  $('recheck').onclick = check;
  $('openDev').onclick = function(){
    $('devMsg').textContent = 'Sending the keys to the TV...';
    api('/api/devsettings', {host: host}).then(function(r){
      $('devMsg').textContent = r.ok ? 'Done. Look at the TV: the Developer Settings screen should be showing.' : r.error;
    }).catch(function(e){ $('devMsg').textContent = e.message; });
  };
  $('showPw').onclick = function(){
    var show = $('pw').type === 'password';
    $('pw').type = show ? 'text' : 'password';
    $('showPw').textContent = show ? 'Hide' : 'Show';
    $('showPw').setAttribute('aria-pressed', show ? 'true' : 'false');
  };
  $('pw').onkeydown = function(e){ if(e.key === 'Enter') $('install').click(); };

  function drawSteps(st){
    var ul = $('steps'); clear(ul);
    (st.steps || []).forEach(function(s){
      var li = el('li');
      var ic = el('span', 'ic ' + (s.state === 'wait' ? '' : s.state), s.state === 'done' ? '✓' : s.state === 'fail' ? '!' : '');
      var box = el('span'); box.appendChild(document.createTextNode(s.label));
      if(s.note){ box.appendChild(el('span', 'note', s.note)); }
      li.appendChild(ic); li.appendChild(box); ul.appendChild(li);
    });
  }

  function poll(){
    api('/api/status').then(function(st){
      drawSteps(st);
      if(st.state === 'running'){ pollTimer = setTimeout(poll, 500); return; }
      busy = false; $('install').disabled = false;
      var r = $('result'); clear(r); r.hidden = false;
      if(st.state === 'done'){
        r.className = 'result ok';
        r.appendChild(el('h3', '', st.message));
        r.appendChild(el('p', '', 'Next: open StreamBoss on the Roku and connect your provider there. You can close this window.'));
        $('n3').className = 'num done';
        $('pwBox').hidden = true;
      } else {
        r.className = 'result bad';
        r.appendChild(el('h3', '', 'It did not install'));
        r.appendChild(el('p', '', st.message || 'Something went wrong.'));
        r.appendChild(el('p', 'muted', 'Fix that and press Install again.'));
      }
    }).catch(function(e){ busy = false; $('install').disabled = false; $('result').hidden = false; $('result').className = 'result bad'; $('result').textContent = e.message; });
  }

  $('install').onclick = function(){
    if(busy) return;
    var pw = $('pw').value;
    if(!pw){ $('result').hidden = false; $('result').className = 'result bad'; $('result').textContent = 'Type the password you chose on the TV.'; $('pw').focus(); return; }
    busy = true; $('install').disabled = true; $('result').hidden = true;
    api('/api/install', {host: host, password: pw}).then(function(){ poll(); })
      .catch(function(e){ busy = false; $('install').disabled = false; $('result').hidden = false; $('result').className = 'result bad'; $('result').textContent = e.message; });
  };

  $('quit').onclick = function(){
    api('/api/quit', {}).catch(function(){}).then(function(){
      document.body.textContent = 'The installer has closed. You can close this tab.';
    });
  };

  scan();
})();
</script>
</body>
</html>
''';
