import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="confirm-dialog"
// See javascript/controllers/application.js for how this is wired up
export default class extends Controller {
  static targets = ["title", "subtitle", "confirmButton"];

  handleConfirm(rawData) {
    const data = this.#normalizeRawData(rawData);

    this.#prepareDialog(data);

    this.element.showModal();

    return new Promise((resolve) => {
      this.element.addEventListener(
        "close",
        () => {
          const isConfirmed = this.element.returnValue === "confirm";
          resolve(isConfirmed);
        },
        { once: true },
      );
    });
  }

  #prepareDialog(data) {
    const variant = data.variant || "primary";

    this.confirmButtonTargets.forEach((button) => {
      if (button.dataset.variant === variant) {
        button.removeAttribute("hidden");
      } else {
        button.setAttribute("hidden", true);
      }

      if (data.confirmText) {
        button.textContent = data.confirmText;
      }
    });

    if (data.title) {
      this.titleTarget.textContent = data.title;
    }
    if (data.body) {
      this.subtitleTarget.innerHTML = data.body;
    }
  }

  // If data is a string, it's the title.  Otherwise, return the parsed object.
  #normalizeRawData(rawData) {
    try {
      const parsed = JSON.parse(rawData);

      if (typeof parsed === "boolean") {
        return {};
      }

      return parsed;
    } catch (e) {
      return { title: rawData };
    }
  }
}
