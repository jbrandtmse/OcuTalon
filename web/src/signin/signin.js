/* Shows or hides the password. Pinned to the page by hash; no other script runs there. ASCII only. */
(function () {
  var button = document.getElementById('ocu-toggle');
  var input = document.getElementById('ocu-pass');
  if (!button || !input) {
    return;
  }
  button.addEventListener('click', function () {
    var show = button.getAttribute('aria-pressed') !== 'true';
    button.setAttribute('aria-pressed', show ? 'true' : 'false');
    input.type = show ? 'text' : 'password';
  });
}());
