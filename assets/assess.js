/* SlateAssess — the browser half of an assessment.
 *
 * A dependency-free CLASSIC script (no modules, no bare specifiers, no framework). That is a deliberate
 * constraint, not an accident: Slate inlines a classic script verbatim into a static export, so the exact
 * bytes that run in the live notebook run in the delivered file, with nothing left to resolve at open
 * time. A locked-down exam browser with no network still gets a working paper.
 *
 * NO MARKING HAPPENS HERE. The correct answers are never sent to the candidate, so there is nothing in
 * this file, or anywhere in the page, to extract. All this does is collect answers, keep them safe, and
 * emit a signed submission.
 *
 * Widgets register through a queue (`__saQueue`) rather than calling in directly, so cells may run in any
 * order — a question that renders before the header simply waits for it.
 */
(function () {
  "use strict";
  if (window.SlateAssess) return;             // one runtime per page, whoever gets there first

  var CFG = null;                             // the Assessment config, once init() has run
  var STATE = { identity: {}, answers: {}, confirmed: false, startedAt: null, expired: false };
  var QUESTION_ELS = {};                      // qid -> the container element
  // Redraw hooks, keyed by ROLE rather than a flat list: re-running a cell re-mounts its widget, and a
  // list would accumulate a stale closure (and, for the header, a second countdown timer) every time.
  var LISTENERS = {};
  var CLOCK_TIMER = null;

  /* ── persistence ──────────────────────────────────────────────────────────────
   * A crashed tab, an accidental reload, or a browser the invigilator restarts must not cost a candidate
   * their paper. Every change is written to localStorage immediately and restored on load. This is the
   * one place this design is strictly better than a reactive-kernel notebook, where the answers live in
   * a server process the page can lose. Storage failures (private mode, a locked-down profile) are
   * swallowed — the paper still works, it just stops being crash-proof. */
  function storeKey() {
    var key = "slateassess:" + (CFG ? CFG.id : "unknown");
    // A served paper has one URL per sitting, so the assessment id alone scopes it correctly. A paper
    // opened as a LOCAL FILE does not: Chrome shares a single localStorage across every `file://` page,
    // so two copies of the same paper sitting in different folders would share — and corrupt — each
    // other's state. Scope by path there. The path is stable across reloads, so crash recovery, which
    // is the whole reason this is persisted, still works.
    if (location.protocol === "file:") key += ":" + location.pathname;
    return key;
  }
  function save() {
    try {
      localStorage.setItem(storeKey(), JSON.stringify({
        identity: STATE.identity, answers: STATE.answers,
        confirmed: STATE.confirmed, startedAt: STATE.startedAt
      }));
    } catch (e) { /* storage unavailable — carry on without a safety net */ }
  }
  function restore() {
    try {
      var raw = localStorage.getItem(storeKey());
      if (!raw) return;
      var d = JSON.parse(raw);
      STATE.identity = d.identity || {};
      STATE.answers = d.answers || {};
      STATE.confirmed = !!d.confirmed;
      STATE.startedAt = d.startedAt || null;
      // A start stamp only means anything once a candidate has actually confirmed and begun. Restoring
      // one WITHOUT a confirmation would silently start — or, if it is old enough, immediately expire —
      // a paper nobody has sat. That is not hypothetical: `file://` shares one localStorage across every
      // local file in Chrome, and the key here is just the assessment id, so a stale stamp left by
      // another copy of the same paper lands in a freshly opened one.
      if (!STATE.confirmed) STATE.startedAt = null;
    } catch (e) { /* corrupt or unreadable — start fresh rather than fail to load */ }
  }

  /* ── canonical message + signing ──────────────────────────────────────────────
   * Mirrors src/hmac.jl EXACTLY. Any divergence makes every signature fail verification, so if you change
   * one side you must change the other. */
  function canon(v) { return String(v == null ? "" : v).replace(/[\r\n\t]+/g, " ").trim(); }

  // An option's recorded NUMBER: its 1-based index, 0 for no response, -1 for flagged. Mirrors
  // `answer_code` in src/types.jl — the two must agree or nothing verifies.
  var ANSWER_NR = 0, ANSWER_FLAG = -1;
  function codeOf(value) {
    if (value == null || String(value).trim() === "" || value === CFG.no_response) return ANSWER_NR;
    if (value === CFG.flag) return ANSWER_FLAG;
    var i = CFG.choices.indexOf(value);
    return i >= 0 ? i + 1 : ANSWER_NR;
  }

  /* What the page can learn about the environment it is running in.
   *
   * Safe Exam Browser injects a `SafeExamBrowser` object with its version and, from SEB 3.x, the
   * Config Key and Browser Exam Key of the .seb configuration that launched it. Capturing those into
   * the SIGNED submission means a paper sat in an ordinary browser is distinguishable from one sat
   * under the exam configuration that was actually issued — the examiner compares the recorded Config
   * Key against the .seb file they distributed.
   *
   * Being straight about the limit: with no server there is nothing to validate these against at the
   * time, and a determined candidate can fake the object. It raises the effort required and it makes
   * the ordinary cases — the paper opened in Chrome, the paper sat under last year's config — visible.
   * The `updateKeys` callback is the documented way to read the keys reliably after a page load. */
  function readEnv() {
    var out = { seb_version: "", seb_config_key: "", seb_browser_exam_key: "" };
    try {
      var S = window.SafeExamBrowser;
      if (!S) return Promise.resolve(out);
      var take = function () {
        out.seb_version = String(S.version || "");
        if (S.security) {
          out.seb_config_key = String(S.security.configKey || "");
          out.seb_browser_exam_key = String(S.security.browserExamKey || "");
        }
        return out;
      };
      if (S.security && typeof S.security.updateKeys === "function") {
        return new Promise(function (res) {
          var settled = false;
          var done = function () { if (!settled) { settled = true; res(take()); } };
          try { S.security.updateKeys(done); } catch (e) { done(); }
          setTimeout(done, 1500);          // never let a missing callback block the submission
        });
      }
      return Promise.resolve(take());
    } catch (e) { return Promise.resolve(out); }
  }

  var ENV_FIELDS = ["seb_version", "seb_config_key", "seb_browser_exam_key"];

  function canonicalMessage(submittedAt, env) {
    var parts = [];
    CFG.identity.forEach(function (f) { parts.push(f.key + "=" + canon(STATE.identity[f.key])); });
    CFG.questions.forEach(function (q) { parts.push(q + "=" + codeOf(STATE.answers[q])); });
    ENV_FIELDS.forEach(function (k) { parts.push(k + "=" + canon(env[k])); });
    parts.push("submitted_at=" + canon(submittedAt));
    return parts.join("\n");
  }

  function hex(buf) {
    return Array.prototype.map.call(new Uint8Array(buf), function (b) {
      return ("0" + b.toString(16)).slice(-2);
    }).join("");
  }

  /* SHA-256 and HMAC in plain JavaScript.
   *
   * This deliberately does NOT use `crypto.subtle`, even though it is the obvious choice. WebCrypto is
   * exposed only in a SECURE CONTEXT, and a `file://` origin is not one in Chrome or in the WKWebView
   * that exam browsers embed on macOS/iOS — `crypto.subtle` is simply `undefined` there. Since the whole
   * point of this package is a paper delivered as a local HTML file, relying on WebCrypto would mean the
   * signature silently failing to exist in exactly the deployment it was built for. A few hundred bytes
   * of message do not need hardware acceleration, so the portable implementation is the correct one.
   *
   * Verified against Julia's `SHA.sha256` and RFC 4231 in the package test suite. */
  var K256 = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2];

  function sha256(msg) {
    var H = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
             0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
    var len = msg.length;
    // Pad: 0x80, then zeros, then the 64-bit big-endian bit length.
    var withPad = new Uint8Array(((len + 9 + 63) >> 6) << 6);
    withPad.set(msg);
    withPad[len] = 0x80;
    var bits = len * 8;
    var dv = new DataView(withPad.buffer);
    dv.setUint32(withPad.length - 8, Math.floor(bits / 4294967296));
    dv.setUint32(withPad.length - 4, bits >>> 0);

    var w = new Uint32Array(64);
    for (var off = 0; off < withPad.length; off += 64) {
      for (var i = 0; i < 16; i++) w[i] = dv.getUint32(off + i * 4);
      for (i = 16; i < 64; i++) {
        var g0 = w[i - 15], g1 = w[i - 2];
        var s0 = ((g0 >>> 7) | (g0 << 25)) ^ ((g0 >>> 18) | (g0 << 14)) ^ (g0 >>> 3);
        var s1 = ((g1 >>> 17) | (g1 << 15)) ^ ((g1 >>> 19) | (g1 << 13)) ^ (g1 >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
      }
      var a = H[0], b = H[1], c = H[2], d = H[3], e = H[4], f = H[5], g = H[6], h = H[7];
      for (i = 0; i < 64; i++) {
        var S1 = ((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^ ((e >>> 25) | (e << 7));
        var ch = (e & f) ^ (~e & g);
        var t1 = (h + S1 + ch + K256[i] + w[i]) >>> 0;
        var S0 = ((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^ ((a >>> 22) | (a << 10));
        var maj = (a & b) ^ (a & c) ^ (b & c);
        var t2 = (S0 + maj) >>> 0;
        h = g; g = f; f = e; e = (d + t1) >>> 0;
        d = c; c = b; b = a; a = (t1 + t2) >>> 0;
      }
      H[0] = (H[0] + a) >>> 0; H[1] = (H[1] + b) >>> 0; H[2] = (H[2] + c) >>> 0; H[3] = (H[3] + d) >>> 0;
      H[4] = (H[4] + e) >>> 0; H[5] = (H[5] + f) >>> 0; H[6] = (H[6] + g) >>> 0; H[7] = (H[7] + h) >>> 0;
    }
    var out = new Uint8Array(32), odv = new DataView(out.buffer);
    for (i = 0; i < 8; i++) odv.setUint32(i * 4, H[i]);
    return out;
  }

  function utf8(str) {
    if (window.TextEncoder) return new TextEncoder().encode(str);
    // TextEncoder is not secure-context gated, so this is belt-and-braces for ancient engines.
    var s = unescape(encodeURIComponent(str)), a = new Uint8Array(s.length);
    for (var i = 0; i < s.length; i++) a[i] = s.charCodeAt(i);
    return a;
  }

  function concat(x, y) {
    var out = new Uint8Array(x.length + y.length);
    out.set(x); out.set(y, x.length);
    return out;
  }

  function hmacSha256(keyStr, msgStr) {
    var block = 64;
    var k = utf8(keyStr);
    if (k.length > block) k = sha256(k);
    var padded = new Uint8Array(block);
    padded.set(k);
    var ipad = new Uint8Array(block), opad = new Uint8Array(block);
    for (var i = 0; i < block; i++) { ipad[i] = padded[i] ^ 0x36; opad[i] = padded[i] ^ 0x5c; }
    return hex(sha256(concat(opad, sha256(concat(ipad, utf8(msgStr))))));
  }


  /* ── status ───────────────────────────────────────────────────────────────── */
  // 'locked' before the candidate confirms their identity, then one of answered / flagged / blank.
  function statusOf(qid) {
    if (!STATE.confirmed) return "locked";
    var v = STATE.answers[qid];
    if (v === CFG.flag) return "flagged";
    if (v == null || v === CFG.no_response) return "blank";
    return "answered";
  }
  var GLYPH = { locked: "🔒", blank: "❌", answered: "✅", flagged: "🚩" };

  function counts() {
    var c = { answered: 0, flagged: 0, blank: 0, locked: 0 };
    CFG.questions.forEach(function (q) { c[statusOf(q)]++; });
    return c;
  }
  function notify() {
    Object.keys(LISTENERS).forEach(function (k) { try { LISTENERS[k](); } catch (e) {} });
  }

  /* ── question widget ───────────────────────────────────────────────────────── */
  function mountQuestion(root, qid) {
    QUESTION_ELS[qid] = root;
    root.classList.add("sa-q");
    root.setAttribute("data-qid", qid);
    root.innerHTML = "";

    var row = document.createElement("div");
    row.className = "sa-q-row";

    var badge = document.createElement("span");
    badge.className = "sa-q-badge";
    row.appendChild(badge);

    var opts = document.createElement("div");
    opts.className = "sa-q-opts";

    // Real radios in a real fieldset: keyboard and screen-reader behaviour comes for free, and a
    // candidate using arrow keys or tab gets what they expect under exam pressure.
    // "No response" and the review flag are both optional. Without the former, unanswered is simply
    // nothing selected (the candidate cannot take an answer back); without the latter there is no
    // flag control. Both still record the same way — 0 and -1 respectively.
    var all = CFG.choices.slice();
    if (CFG.show_no_response !== false) all.push(CFG.no_response);
    if (CFG.flag) all.push(CFG.flag);

    all.forEach(function (choice) {
      var id = "sa-" + qid + "-" + choice.replace(/[^a-zA-Z0-9]/g, "_");
      var lab = document.createElement("label");
      lab.className = "sa-opt";
      lab.setAttribute("for", id);
      if (choice === CFG.no_response) lab.classList.add("sa-opt-nr");
      if (choice === CFG.flag) lab.classList.add("sa-opt-flag");

      var input = document.createElement("input");
      input.type = "radio";
      input.name = "sa-" + qid;
      input.id = id;
      input.value = choice;
      input.addEventListener("change", function () {
        if (!STATE.confirmed || STATE.expired) return;
        STATE.answers[qid] = choice;
        save();
        refreshQuestion(qid);
        notify();
      });

      var txt = document.createElement("span");
      txt.textContent = choice;
      lab.appendChild(input);
      lab.appendChild(txt);
      opts.appendChild(lab);
    });

    row.appendChild(opts);
    root.appendChild(row);
    refreshQuestion(qid);
  }

  function refreshQuestion(qid) {
    var root = QUESTION_ELS[qid];
    if (!root) return;
    var st = statusOf(qid);
    var cur = STATE.answers[qid] == null ? CFG.no_response : STATE.answers[qid];
    root.setAttribute("data-status", st);
    var badge = root.querySelector(".sa-q-badge");
    if (badge) badge.textContent = GLYPH[st];
    Array.prototype.forEach.call(root.querySelectorAll("input[type=radio]"), function (i) {
      i.checked = (i.value === cur);
      i.disabled = !STATE.confirmed || STATE.expired;
    });
  }
  function refreshAll() { Object.keys(QUESTION_ELS).forEach(refreshQuestion); }

  /* ── header: identity gate, countdown, live tally ──────────────────────────── */
  var HEADER_EL = null;                       // kept so `reset()` can rebuild the identity form

  function mountHeader(root) {
    HEADER_EL = root;
    root.className = "sa-header";
    root.innerHTML = "";

    var title = document.createElement("div");
    title.className = "sa-title";
    title.textContent = CFG.title;
    root.appendChild(title);

    if (CFG.subtitle) {
      var sub = document.createElement("div");
      sub.className = "sa-subtitle";
      sub.textContent = CFG.subtitle;
      root.appendChild(sub);
    }

    var form = document.createElement("div");
    form.className = "sa-idform";

    var inputs = {};
    CFG.identity.forEach(function (f) {
      var wrap = document.createElement("label");
      wrap.className = "sa-idfield";
      var lab = document.createElement("span");
      lab.textContent = f.label + (f.required ? " *" : "");
      var inp = document.createElement("input");
      inp.type = "text";
      inp.value = STATE.identity[f.key] || "";
      inp.placeholder = f.placeholder || "";
      if (f.help) inp.title = f.help;
      inp.addEventListener("input", function () {
        STATE.identity[f.key] = inp.value;
        save();
        validate();
      });
      inputs[f.key] = inp;
      wrap.appendChild(lab);
      wrap.appendChild(inp);
      form.appendChild(wrap);
    });
    root.appendChild(form);

    var err = document.createElement("div");
    err.className = "sa-iderr";
    root.appendChild(err);

    var actions = document.createElement("div");
    actions.className = "sa-actions";
    var confirm = document.createElement("button");
    confirm.className = "sa-confirm";
    actions.appendChild(confirm);

    var tally = document.createElement("span");
    tally.className = "sa-tally";
    actions.appendChild(tally);

    var clock = document.createElement("span");
    clock.className = "sa-clock";
    actions.appendChild(clock);
    root.appendChild(actions);

    // Identity is checked against each field's pattern; the FIRST failing field is named, because a
    // candidate mistyping their number under time pressure needs to know which box is wrong.
    function problems() {
      var out = [];
      CFG.identity.forEach(function (f) {
        var v = (STATE.identity[f.key] || "").trim();
        if (f.required && !v) { out.push(f.label + " is required"); return; }
        if (v && f.pattern) {
          var re;
          try { re = new RegExp(f.pattern); } catch (e) { return; }
          if (!re.test(v)) out.push(f.label + " doesn't look right");
        }
      });
      return out;
    }

    function validate() {
      var probs = problems();
      var ok = probs.length === 0;
      confirm.disabled = !ok && !STATE.confirmed;
      err.textContent = STATE.confirmed ? "" : (probs.length ? probs[0] : "");
      confirm.textContent = STATE.confirmed ? "Locked in — click to edit details" : "Confirm and start";
      root.setAttribute("data-confirmed", STATE.confirmed ? "1" : "0");
      CFG.identity.forEach(function (f) { inputs[f.key].disabled = STATE.confirmed; });
      var c = counts();
      tally.textContent = STATE.confirmed
        ? c.answered + " answered · " + c.flagged + " flagged · " + c.blank + " blank"
        : CFG.questions.length + " questions";
      return ok;
    }

    confirm.addEventListener("click", function () {
      if (STATE.confirmed) {
        // Re-opening the details does NOT discard answers — a mistyped number should be fixable without
        // costing the candidate everything they have entered.
        STATE.confirmed = false;
      } else {
        if (problems().length) return;
        STATE.confirmed = true;
        if (!STATE.startedAt) STATE.startedAt = new Date().toISOString();
      }
      save();
      validate();
      refreshAll();
      notify();
    });

    // Countdown. Anchored to the FIRST confirm (persisted), so a reload doesn't hand back extra time.
    function tick() {
      // The clock is meaningless until the candidate has confirmed and started: no countdown, and in
      // particular no way to reach "time is up" on a paper that was never begun.
      if (!CFG.duration || !STATE.confirmed || !STATE.startedAt) {
        clock.textContent = "";
        clock.classList.remove("sa-clock-low", "sa-clock-out");
        return;
      }
      var end = new Date(STATE.startedAt).getTime() + CFG.duration * 60000;
      var left = end - Date.now();
      if (left <= 0) {
        clock.textContent = "time is up";
        clock.classList.add("sa-clock-out");
        if (!STATE.expired) { STATE.expired = true; refreshAll(); notify(); }
        return;
      }
      var mins = Math.floor(left / 60000), secs = Math.floor((left % 60000) / 1000);
      clock.textContent = mins + "m " + ("0" + secs).slice(-2) + "s left";
      clock.classList.toggle("sa-clock-low", left < 5 * 60000);
    }
    if (CLOCK_TIMER) clearInterval(CLOCK_TIMER);
    CLOCK_TIMER = setInterval(tick, 1000);

    LISTENERS.header = function () { validate(); tick(); };
    validate();
    tick();
  }

  /* ── status strip: jump to any question, see what's left ───────────────────── */
  function mountStatus(root) {
    root.className = "sa-status";
    function draw() {
      root.innerHTML = "";
      CFG.questions.forEach(function (q, i) {
        var b = document.createElement("button");
        b.className = "sa-chip";
        b.setAttribute("data-status", statusOf(q));
        b.textContent = String(i + 1);
        b.title = q + " — " + statusOf(q);
        b.addEventListener("click", function () {
          var el = QUESTION_ELS[q];
          if (el) el.scrollIntoView({ behavior: "smooth", block: "center" });
        });
        root.appendChild(b);
      });
    }
    LISTENERS.status = draw;
    draw();
  }

  /* ── reset control (authoring aid) ─────────────────────────────────────────── */
  // A visible button for `reset()`. Meant for writing and demonstrating a paper, where the countdown
  // expiring — or state left behind by an earlier run — otherwise leaves you locked out with no route
  // back. Leave it out of a real sitting; see `reset_button` in src/render.jl.
  function mountReset(root) {
    root.className = "sa-reset";
    root.innerHTML = "";
    var b = document.createElement("button");
    b.className = "sa-resetbtn";
    b.type = "button";
    b.textContent = "↺ Reset paper";
    b.title = "Clear identity, answers and the countdown, and start the paper over.";
    b.addEventListener("click", function () {
      API.reset();
      b.textContent = "↺ Reset — done";
      setTimeout(function () { b.textContent = "↺ Reset paper"; }, 1200);
    });
    root.appendChild(b);
  }

  /* ── submission ────────────────────────────────────────────────────────────── */
  function csvCell(v) {
    var s = canon(v);
    return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
  }

  function buildCsv(submittedAt, signature, env) {
    var head = [], row = [];
    CFG.identity.forEach(function (f) { head.push(f.key); row.push(STATE.identity[f.key] || ""); });
    head.push("started_at"); row.push(STATE.startedAt || "");
    head.push("submitted_at"); row.push(submittedAt);
    // Numeric codes, not labels — see `codeOf`.
    CFG.questions.forEach(function (q) { head.push(q); row.push(codeOf(STATE.answers[q])); });
    ENV_FIELDS.forEach(function (k) { head.push(k); row.push(env[k] || ""); });
    head.push("signature"); row.push(signature);
    return head.map(csvCell).join(",") + "\n" + row.map(csvCell).join(",") + "\n";
  }

  function mountSubmission(root) {
    root.className = "sa-submit";
    root.innerHTML = "";

    var summary = document.createElement("div");
    summary.className = "sa-summary";
    root.appendChild(summary);

    var btnRow = document.createElement("div");
    btnRow.className = "sa-actions";
    var make = document.createElement("button");
    make.className = "sa-make";
    make.textContent = "Produce my submission file";
    btnRow.appendChild(make);
    root.appendChild(btnRow);

    var out = document.createElement("div");
    out.className = "sa-out";
    out.style.display = "none";
    root.appendChild(out);

    function drawSummary() {
      var c = counts();
      if (!STATE.confirmed) {
        summary.textContent = "Enter and confirm your details at the top of the paper to begin.";
        make.disabled = true;
        return;
      }
      make.disabled = false;
      summary.innerHTML = "";
      var line = document.createElement("div");
      line.innerHTML = "<b>" + c.answered + "</b> answered · <b>" + c.flagged +
        "</b> flagged for review · <b>" + c.blank + "</b> left blank";
      summary.appendChild(line);
      if (c.flagged) {
        var warn = document.createElement("div");
        warn.className = "sa-warn";
        warn.textContent = "Questions still marked " + CFG.flag +
          " are recorded as unanswered. Clear the flag and choose an option to have them count.";
        summary.appendChild(warn);
      }
    }
    LISTENERS.submission = drawSummary;
    drawSummary();

    make.addEventListener("click", function () {
      var submittedAt = new Date().toISOString();
      readEnv().then(function (env) {
        var signature = hmacSha256(CFG.session_key, canonicalMessage(submittedAt, env));
        var csv = buildCsv(submittedAt, signature, env);
        var primary = canon(STATE.identity[CFG.identity[0].key]) || "submission";
        var name = primary.replace(/[^A-Za-z0-9_.-]/g, "_") + ".csv";

        out.innerHTML = "";
        out.style.display = "";

        var ok = document.createElement("div");
        ok.className = "sa-ok";
        ok.textContent = "Submission produced at " + submittedAt +
          ". Hand in the file below exactly as it is — editing it invalidates the signature.";
        out.appendChild(ok);

        var row = document.createElement("div");
        row.className = "sa-actions";

        // Primary route: a real download. Some locked-down browsers disable downloads entirely, which is
        // why the copy-out box below is not a nicety — it is the fallback that keeps the paper submittable.
        var dl = document.createElement("button");
        dl.className = "sa-dl";
        dl.textContent = "⬇ Download " + name;
        dl.addEventListener("click", function () {
          try {
            var blob = new Blob([csv], { type: "text/csv" });
            var url = URL.createObjectURL(blob);
            var a = document.createElement("a");
            a.href = url; a.download = name;
            document.body.appendChild(a); a.click(); a.remove();
            setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
          } catch (e) {
            ok.textContent = "This browser blocked the download — copy the text below instead.";
          }
        });
        row.appendChild(dl);

        var copy = document.createElement("button");
        copy.className = "sa-copy";
        copy.textContent = "Copy submission text";
        copy.addEventListener("click", function () {
          ta.select();
          try { document.execCommand("copy"); } catch (e) {}
          if (navigator.clipboard) navigator.clipboard.writeText(csv).catch(function () {});
          copy.textContent = "Copied";
          setTimeout(function () { copy.textContent = "Copy submission text"; }, 1500);
        });
        row.appendChild(copy);
        out.appendChild(row);

        var ta = document.createElement("textarea");
        ta.className = "sa-csv";
        ta.readOnly = true;
        ta.rows = 4;
        ta.value = csv;
        out.appendChild(ta);
      });
    });
  }

  /* ── public entry points + the deferred-registration queue ─────────────────── */
  var API = {
    // Re-running the header cell must not wipe answers already entered, so the config is only taken
    // once — but the queue is ALWAYS drained, because widgets whose cells ran first are sitting in it
    // waiting for exactly this call.
    init: function (cfg) {
      if (!CFG) { CFG = cfg; restore(); }
      API._drain();
    },

    _drain: function () {
      if (!CFG) return;                        // nothing can mount until the header has supplied config
      var q = window.__saQueue || [];
      window.__saQueue = [];
      q.forEach(function (item) {
        try {
          if (item[0] === "header") mountHeader(item[1]);
          else if (item[0] === "question") mountQuestion(item[1], item[2]);
          else if (item[0] === "status") mountStatus(item[1]);
          else if (item[0] === "submission") mountSubmission(item[1]);
          else if (item[0] === "reset") mountReset(item[1]);
        } catch (e) {
          // One broken widget must never take the rest of the paper down with it.
          try {
            item[1].innerHTML = '<div class="sa-err">This element failed to load: ' +
              String(e && e.message || e) + "</div>";
          } catch (_) {}
        }
      });
      notify();
    },

    // Escape hatch for an invigilator: read the current state from the browser console.
    _state: function () { return { config: CFG, state: STATE, counts: CFG ? counts() : null }; },

    /* Wipe everything and start over — identity, answers, and the countdown's start stamp.
     *
     * This exists for AUTHORING. While writing a paper you re-run it constantly, and the persistence
     * that makes the clock tamper-resistant for a candidate (the start time survives reloads, and
     * un-confirming deliberately does not clear it) otherwise leaves you with no way back to a fresh
     * paper short of clearing localStorage by hand.
     *
     * It grants a candidate nothing they did not already have: anyone who can open a console can clear
     * localStorage directly. Which is the honest position on the timer generally — in a design with no
     * server, the countdown is a courtesy to the candidate, not an enforcement mechanism. What actually
     * evidences timing is `started_at`/`submitted_at` in the SIGNED submission, read against the
     * wall-clock window the sitting was invigilated over. */
    reset: function () {
      try { localStorage.removeItem(storeKey()); } catch (e) {}
      STATE.identity = {}; STATE.answers = {};
      STATE.confirmed = false; STATE.startedAt = null; STATE.expired = false;
      if (HEADER_EL) mountHeader(HEADER_EL);       // rebuild the form so the input boxes clear too
      refreshAll();
      notify();
      return "SlateAssess: reset";
    }
  };

  window.SlateAssess = API;
  API._drain();                               // no-op until init() supplies the config
})();
