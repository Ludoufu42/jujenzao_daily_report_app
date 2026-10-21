// Google 登入(Google Identity Services)。只取 ID token,交給 Dart 端送到 Worker 驗證。
(function () {
  var KEY = 'jz_id_token';
  var state = { cb: null, inited: false };

  function ready() {
    return !!(window.google && window.google.accounts && window.google.accounts.id);
  }
  function parse(t) {
    try {
      var p = t.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
      p += '='.repeat((4 - (p.length % 4)) % 4);
      return JSON.parse(decodeURIComponent(escape(atob(p))));
    } catch (e) { return null; }
  }

  window.jzGoogle = {
    ready: ready,
    init: function (clientId, cb) {
      state.cb = cb;
      if (state.inited) return true;
      if (!ready()) return false;
      window.google.accounts.id.initialize({
        client_id: clientId,
        callback: function (r) {
          try { localStorage.setItem(KEY, r.credential); } catch (e) {}
          if (state.cb) state.cb(r.credential);
        },
        auto_select: true,
        cancel_on_tap_outside: false
      });
      state.inited = true;
      return true;
    },
    saved: function () {
      try {
        var t = localStorage.getItem(KEY);
        if (!t) return '';
        var p = parse(t);
        if (!p || p.exp * 1000 < Date.now() + 60000) { localStorage.removeItem(KEY); return ''; }
        return t;
      } catch (e) { return ''; }
    },
    prompt: function () { if (ready()) window.google.accounts.id.prompt(); },
    makeButton: function () {
      var d = document.createElement('div');
      d.style.width = '100%';
      d.style.height = '100%';
      d.style.display = 'flex';
      d.style.justifyContent = 'center';
      if (ready()) {
        window.google.accounts.id.renderButton(d, {
          theme: 'outline', size: 'large', text: 'signin_with',
          shape: 'rectangular', locale: 'zh-TW', width: 280
        });
      }
      return d;
    },
    signOut: function () {
      try { localStorage.removeItem(KEY); } catch (e) {}
      if (ready()) window.google.accounts.id.disableAutoSelect();
    }
  };
})();
