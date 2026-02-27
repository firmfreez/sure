// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails";
import "controllers";

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
  // Use "replace" to avoid adding form submission to browser history
  Turbo.visit(this.target, { action: "replace" });
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
