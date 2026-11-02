/*
  Two small behaviors, the only script of the page, pinned to it by hash. ASCII only.
  The password toggle shows or hides the password.
  The form carries the address's fragment through sign-in: the server's redirect names no fragment, so the browser
  gives the page it lands on the fragment of the address that the form was posted to.
*/
(function () {
  var form = document.forms.Login;
  if (form) {
    form.addEventListener('submit', function () {
      var action = form.getAttribute('action') || '';
      if (location.hash && action.indexOf('#') < 0) {
        form.setAttribute('action', action + location.hash);
      }
    });
  }
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
