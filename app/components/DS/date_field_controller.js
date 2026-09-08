import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["input"];
  static values = { timeZone: String, saveUrl: String };

  today() {
    const parts = new Intl.DateTimeFormat("en", {
      timeZone: this.timeZoneValue,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).formatToParts(new Date());
    const values = Object.fromEntries(
      parts.map(({ type, value }) => [type, value]),
    );
    this.inputTarget.value = `${values.year}-${values.month}-${values.day}`;
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }));
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }));
  }

  async remember() {
    if (
      !this.saveUrlValue ||
      !this.inputTarget.value ||
      !this.inputTarget.validity.valid
    )
      return;

    this.pendingDate = this.inputTarget.value;
    if (this.saving) return;

    this.saving = true;
    try {
      // Serialize updates so an earlier request cannot overwrite a newer date.
      while (this.pendingDate) {
        const date = this.pendingDate;
        this.pendingDate = null;
        const response = await fetch(this.saveUrlValue, {
          method: "PATCH",
          headers: {
            "Content-Type": "application/json",
            Accept: "application/json",
            "X-CSRF-Token":
              document.querySelector('meta[name="csrf-token"]')?.content || "",
          },
          body: JSON.stringify({ user: { last_entry_date: date } }),
          keepalive: true,
        });
        if (!response.ok)
          throw new Error(`Date preference update failed: ${response.status}`);
      }
    } catch (error) {
      console.warn("Unable to remember entry date", error);
    } finally {
      this.saving = false;
    }
  }
}
