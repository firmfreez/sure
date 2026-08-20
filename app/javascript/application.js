// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails";
import "controllers";
import HwComboboxController from "controllers/hw_combobox_controller";

// Fix hotwire_combobox race condition: when typing quickly, a slow response for
// an early query (e.g. "A") can overwrite the correct results for the final query
// (e.g. "AAPL"). We abort the previous in-flight request whenever a new one fires,
// so stale Turbo Stream responses never reach the DOM.
const originalFilterAsync = HwComboboxController.prototype._filterAsync;
HwComboboxController.prototype._filterAsync = async function(inputType) {
  if (this._searchAbortController) {
    this._searchAbortController.abort();
  }
  this._searchAbortController = new AbortController();

  const query = {
    q: this._fullQuery,
    input_type: inputType,
    for_id: this.element.dataset.asyncId,
    callback_id: this._enqueueCallback()
  };

  const url = new URL(this.asyncSrcValue, window.location.origin);
  Object.entries(query).forEach(([k, v]) => {
    if (v != null) url.searchParams.set(k, v);
  });

  try {
    const response = await fetch(url.toString(), {
      headers: {
        "Accept": "text/vnd.turbo-stream.html, text/html, application/xhtml+xml",
        "X-Requested-With": "XMLHttpRequest",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
      },
      signal: this._searchAbortController.signal,
      credentials: "same-origin"
    });

    if (response.ok) {
      await Turbo.renderStreamMessage(await response.text());
    }
  } catch (e) {
    if (e.name !== "AbortError") throw e;
  }
};

function closeOpenDialogs() {
  document.querySelectorAll("dialog[open]").forEach((dialog) => {
    if (typeof dialog.close === "function") dialog.close();
  });

  // Clear frame content so modal/drawer disappears immediately before navigation finishes.
  ["modal", "drawer"].forEach((frameId) => {
    const frame = document.getElementById(frameId);
    if (frame) frame.innerHTML = "";
  });
}

Turbo.StreamActions.redirect = function () {
  closeOpenDialogs();
  const targetUrl = new URL(this.target, window.location.origin);
  const currentUrl = new URL(window.location.href);

  if (
    targetUrl.pathname === currentUrl.pathname &&
    targetUrl.search === currentUrl.search &&
    targetUrl.hash === currentUrl.hash
  ) {
    window.location.reload();
    return;
  }

  // Use "replace" to avoid adding form submission to browser history
  Turbo.visit(targetUrl.toString(), { action: "replace" });
};

// Register service worker for PWA offline support
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/service-worker')
      .then(registration => {
        console.log('Service Worker registered with scope:', registration.scope);
      })
      .catch(error => {
        console.log('Service Worker registration failed:', error);
      });
  });
}
