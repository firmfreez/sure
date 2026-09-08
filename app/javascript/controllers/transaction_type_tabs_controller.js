import { Controller } from "@hotwired/stimulus";

// Expense / income tabs render as a DS::SegmentedControl. Switching is
// client-side here: it updates the form's hidden nature field and flips the
// active segment without navigating (the href is a progressive-enhancement
// fallback). Transfer is a plain link to the transfer form.
export default class extends Controller {
  static targets = ["tab", "natureField", "date", "dateLink"];

  connect() {
    this.updateDateLinks();
  }

  updateDateLinks() {
    if (!this.hasDateTarget) return;

    this.dateLinkTargets.forEach((link) => {
      const url = new URL(link.href);
      url.searchParams.set("date", this.dateTarget.value);
      link.href = url.toString();
    });
  }

  selectTab(event) {
    if (!this.hasNatureFieldTarget) return;

    event.preventDefault();

    const selectedTab = event.currentTarget;
    this.natureFieldTarget.value = selectedTab.dataset.nature;

    this.tabTargets.forEach((tab) => {
      const isActive = tab === selectedTab;
      tab.classList.toggle("segmented-control__segment--active", isActive);
      if (isActive) {
        tab.setAttribute("aria-current", "true");
      } else {
        tab.removeAttribute("aria-current");
      }
    });
  }
}
