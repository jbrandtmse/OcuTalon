/*
  The splash screen's script, the only script of the page, pinned to it by hash. ASCII only.
  The copy buttons write a value to the clipboard: "Copied" shows in the row for 2 seconds, and a failure shows the card's failure
  line and selects the value (an input takes the focus first, so that the selection shows and can be copied by hand). Both texts are
  read from the page, and each result is announced through the one polite live region, which is emptied first so that a repeated
  text is spoken again.
  The next reset's time and countdown are filled in the browser's zone and hour format, as web/src/app/chat/page-time.ts writes
  them (pageTime and countdownText; the words below are WHEN_TEXTS' countdown words), and recounted every second. Once the reset
  has passed, it rolls forward by the interval.
  The form carries the address's fragment through sign-in: the server's redirect names no fragment, so the browser gives the page
  it lands on the fragment of the address that the form was posted to.
*/
(function () {
  var COPIED_MS = 2000;
  var WORDS = {
    seconds: 'in {n} s',
    secondsOne: 'in {n} second',
    secondsOther: 'in {n} seconds',
    minutes: 'in {n} min',
    minutesOne: 'in {n} minute',
    minutesOther: 'in {n} minutes',
    hours: 'in {h} h {m} min',
    hoursOne: 'in {h} hour {m} {minutes}',
    hoursOther: 'in {h} hours {m} {minutes}',
    minuteOne: 'minute',
    minuteOther: 'minutes'
  };
  var live = document.getElementById('ocu-live');

  var announceTimer = 0;

  function announce(text) {
    if (live && text) {
      live.textContent = '';
      window.clearTimeout(announceTimer);
      announceTimer = window.setTimeout(function () {
        live.textContent = text;
      }, 50);
    }
  }

  function selectValue(source) {
    if (source.tagName === 'INPUT') {
      source.focus();
      source.setSelectionRange(0, source.value.length);
      return;
    }
    var range = document.createRange();
    range.selectNodeContents(source);
    var selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
  }

  function copyFrom(button) {
    var source = document.getElementById(button.getAttribute('data-copy'));
    var row = button.closest('[data-row]');
    var card = button.closest('[data-card]');
    if (!source || !row || !card) {
      return;
    }
    var failure = card.querySelector('[data-failure]');
    var copied = row.querySelector('[data-copied]');
    var value = source.tagName === 'INPUT' ? source.value : source.textContent;

    function succeeded() {
      if (failure) {
        failure.hidden = true;
      }
      if (copied) {
        copied.hidden = false;
        window.clearTimeout(row.copiedTimer);
        row.copiedTimer = window.setTimeout(function () {
          copied.hidden = true;
        }, COPIED_MS);
        announce(copied.textContent);
      }
    }

    function failed() {
      if (failure) {
        failure.hidden = false;
        announce(failure.textContent);
      }
      selectValue(source);
    }

    var clipboard = navigator.clipboard;
    if (!clipboard || typeof clipboard.writeText !== 'function') {
      failed();
      return;
    }
    var written;
    try {
      written = clipboard.writeText(value);
    } catch (error) {
      failed();
      return;
    }
    Promise.resolve(written).then(succeeded, failed);
  }

  function fill(template, values) {
    return template.replace(/\{(\w+)\}/g, function (all, name) {
      return values[name] === undefined ? '' : values[name];
    });
  }

  function countdown(due, now) {
    var seconds = Math.max(0, Math.ceil((due - now) / 1000));
    function plural(n, one, other) {
      return fill(n === 1 ? one : other, { n: String(n) });
    }
    if (seconds < 60) {
      return { text: fill(WORDS.seconds, { n: String(seconds) }), spoken: plural(seconds, WORDS.secondsOne, WORDS.secondsOther) };
    }
    if (seconds < 3600) {
      var whole = Math.floor(seconds / 60);
      return { text: fill(WORDS.minutes, { n: String(whole) }), spoken: plural(whole, WORDS.minutesOne, WORDS.minutesOther) };
    }
    var hours = Math.floor(seconds / 3600);
    var minutes = Math.floor((seconds % 3600) / 60);
    return {
      text: fill(WORDS.hours, { h: String(hours), m: String(minutes) }),
      spoken: fill(hours === 1 ? WORDS.hoursOne : WORDS.hoursOther, {
        h: String(hours),
        m: String(minutes),
        minutes: minutes === 1 ? WORDS.minuteOne : WORDS.minuteOther
      })
    };
  }

  function timeFormat() {
    return new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' });
  }

  function startCountdown() {
    var stamp = document.getElementById('ocu-reset-time');
    var shown = document.getElementById('ocu-countdown');
    var spoken = document.getElementById('ocu-countdown-spoken');
    if (!stamp || !shown || !spoken) {
      return;
    }
    var due = Date.parse(stamp.getAttribute('datetime'));
    var step = Number(stamp.getAttribute('data-step')) * 1000;
    if (isNaN(due)) {
      return;
    }
    var formatter = timeFormat();
    var first = due;
    var drawn = NaN;

    function tick() {
      var now = Date.now();
      if (step > 0 && due <= now) {
        due += (Math.floor((now - due) / step) + 1) * step;
      }
      if (due !== drawn) {
        drawn = due;
        stamp.textContent = formatter.format(new Date(due));
        if (due !== first) {
          stamp.setAttribute('datetime', new Date(due).toISOString());
        }
      }
      var left = countdown(due, now);
      shown.textContent = left.text;
      spoken.textContent = left.spoken;
    }

    tick();
    window.setInterval(tick, 1000);
  }

  function fillErrorTime() {
    var stamp = document.getElementById('ocu-error-time');
    if (!stamp) {
      return;
    }
    var at = Date.parse(stamp.getAttribute('datetime'));
    if (isNaN(at)) {
      return;
    }
    stamp.textContent = timeFormat().format(new Date(at));
  }

  var form = document.forms.Login;
  if (form) {
    form.addEventListener('submit', function () {
      var action = form.getAttribute('action') || '';
      if (location.hash && action.indexOf('#') < 0) {
        form.setAttribute('action', action + location.hash);
      }
    });
  }
  var buttons = document.querySelectorAll('[data-copy]');
  for (var i = 0; i < buttons.length; i += 1) {
    buttons[i].addEventListener('click', function (event) {
      copyFrom(event.currentTarget);
    });
  }
  startCountdown();
  fillErrorTime();
}());
