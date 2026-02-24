import { Controller } from "@hotwired/stimulus";

// Auto-fit donut center text so it stays inside the ring at any size.
export default class extends Controller {
  static targets = ["title", "amount", "sub"];

  static values = {
    titleMin: { type: Number, default: 11 },
    titleMax: { type: Number, default: 18 },
    amountMin: { type: Number, default: 16 },
    amountMax: { type: Number, default: 36 },
    subMin: { type: Number, default: 11 },
    subMax: { type: Number, default: 18 },
    titleWidthRatio: { type: Number, default: 0.7 },
    amountWidthRatio: { type: Number, default: 0.8 },
    subWidthRatio: { type: Number, default: 0.6 },
  };

  connect() {
    this._fit();
    this._resizeObserver = new ResizeObserver(() => this._fit());
    this._resizeObserver.observe(this.element);
  }

  disconnect() {
    this._resizeObserver?.disconnect();
  }

  _fit() {
    const rect = this.element.getBoundingClientRect();
    if (!rect.width) return;

    this._fitTarget(
      this.titleTarget,
      rect.width * this.titleWidthRatioValue,
      this.titleMinValue,
      this.titleMaxValue,
    );
    this._fitTarget(
      this.amountTarget,
      rect.width * this.amountWidthRatioValue,
      this.amountMinValue,
      this.amountMaxValue,
    );
    if (this.hasSubTarget) {
      this._fitTarget(
        this.subTarget,
        rect.width * this.subWidthRatioValue,
        this.subMinValue,
        this.subMaxValue,
      );
    }
  }

  _fitTarget(target, maxWidth, min, max) {
    if (!target) return;

    target.style.fontSize = `${max}px`;
    const measured = target.scrollWidth;
    if (!measured) return;

    const scale = Math.min(1, maxWidth / measured);
    const nextSize = Math.max(min, Math.floor(max * scale));
    target.style.fontSize = `${nextSize}px`;
  }
}
