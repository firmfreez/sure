import { Controller } from "@hotwired/stimulus";
import evaluateAmountExpression from "utils/evaluate_amount_expression";

// Expense / income tabs render as a DS::SegmentedControl. Switching is
// client-side here: it updates the form's hidden nature field and flips the
// active segment without navigating (the href is a progressive-enhancement
// fallback). Links between forms carry the current draft in their URL.
export default class extends Controller {
  static targets = ["link", "natureField", "date", "amount", "name", "account"];

  connect() {
    this.draftName = this.hasNameTarget ? this.nameTarget.value : "";
    this.updateDateLinks();
  }

  rememberName(event) {
    const widget = this.nameTarget.closest('[data-controller~="hw-combobox"]');
    if (
      event.target === this.nameTarget ||
      (widget?.contains(event.target) &&
        event.target.getAttribute("role") === "combobox")
    ) {
      this.draftName = event.target.value;
    }
  }

  preserveName(event) {
    if (event?.detail?.display) this.draftName = event.detail.display;
    if (!event && this.nameTarget.value) this.draftName = this.nameTarget.value;
    if (!this.draftName) return;

    // Async suggestions can finish after the combobox closes and clears its query.
    const widget = this.nameTarget.closest('[data-controller~="hw-combobox"]');
    if (widget) {
      widget.querySelectorAll('[role="combobox"]').forEach((input) => {
        input.value = this.draftName;
      });
    } else {
      this.nameTarget.value = this.draftName;
    }
  }

  updateDateLinks() {
    if (!this.hasDateTarget) return;

    this.linkTargets.forEach((link) => {
      const url = new URL(link.href);
      url.searchParams.set("date", this.dateTarget.value);
      link.href = url.toString();
    });
  }

  selectTab(event) {
    this.preserveName();
    const selectedTab = event.currentTarget;
    if (!this.hasNatureFieldTarget || !selectedTab.dataset.nature) {
      this.carryDraft(event);
      return;
    }

    event.preventDefault();

    this.natureFieldTarget.value = selectedTab.dataset.nature;

    this.linkTargets.forEach((tab) => {
      const isActive = tab === selectedTab;
      tab.classList.toggle("segmented-control__segment--active", isActive);
      if (isActive) {
        tab.setAttribute("aria-current", "true");
      } else {
        tab.removeAttribute("aria-current");
      }
    });
  }

  carryDraft(event) {
    const link = event.currentTarget;
    const url = new URL(link.href);
    const rawAmount = this.amountTarget.value.trim();
    const amount = evaluateAmountExpression(rawAmount);
    if (rawAmount && amount === null) {
      event.preventDefault();
      this.amountTarget.reportValidity();
      return;
    }

    url.searchParams.set("draft_amount", amount === null ? "" : String(amount));
    url.searchParams.set("draft_name", this.nameTarget.value);
    url.searchParams.set("date", this.dateTarget.value);

    if (this.hasAccountTarget) {
      const accountParam = link.dataset.nature
        ? "account_id"
        : "from_account_id";
      url.searchParams.set(accountParam, this.accountTarget.value);
    }

    link.href = url.toString();
  }
}
