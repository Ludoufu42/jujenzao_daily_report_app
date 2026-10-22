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
    // 回傳內建瀏覽器的名稱(LINE、Facebook…),不是內建瀏覽器就回傳空字串。
    // Google 不允許在這些瀏覽器裡登入,要請使用者改用 Safari / Chrome 開。
    inAppBrowser: function () {
      var ua = navigator.userAgent || '';
      if (/Line\//i.test(ua)) return 'LINE';
      if (/FBAN|FBAV|FB_IAB/i.test(ua)) return 'Facebook';
      if (/Instagram/i.test(ua)) return 'Instagram';
      if (/MicroMessenger/i.test(ua)) return '微信';
      if (/Messenger/i.test(ua)) return 'Messenger';
      if (/Twitter/i.test(ua)) return 'Twitter';
      if (/Android/i.test(ua) && /; wv\)/i.test(ua)) return 'App 內建瀏覽器';
      return '';
    },
    signOut: function () {
      try { localStorage.removeItem(KEY); } catch (e) {}
      if (ready()) window.google.accounts.id.disableAutoSelect();
    }
  };
})();
