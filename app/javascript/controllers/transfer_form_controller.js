import ExchangeRateFormController from "controllers/exchange_rate_form_controller";

// Connects to data-controller="transfer-form"
export default class extends ExchangeRateFormController {
  static targets = [
    ...ExchangeRateFormController.targets,
    "fromAccount",
    "toAccount",
  ];

  connect() {
    this.previousFromAccount = this.hasFromAccountTarget
      ? this.fromAccountTarget.value
      : "";
    super.connect();
  }

  fromAccountChanged() {
    const previous = this.previousFromAccount;
    const current = this.fromAccountTarget.value;
    this.previousFromAccount = current;

    if (
      previous &&
      current &&
      current !== previous &&
      (!this.toAccountTarget.value || this.toAccountTarget.value === current)
    ) {
      const select = this.toAccountTarget.closest(
        '[data-controller~="select"]',
      );
      const controller = this.application.getControllerForElementAndIdentifier(
        select,
        "select",
      );
      if (controller?.setValue(previous)) return;
    }

    this.checkCurrencyDifference();
  }

  hasRequiredExchangeRateTargets() {
    if (
      !this.hasFromAccountTarget ||
      !this.hasToAccountTarget ||
      !this.hasDateTarget
    ) {
      return false;
    }

    return true;
  }

  getExchangeRateContext() {
    if (!this.hasRequiredExchangeRateTargets()) {
      return null;
    }

    const fromAccountId = this.fromAccountTarget.value;
    const toAccountId = this.toAccountTarget.value;
    const date = this.dateTarget.value;

    if (!fromAccountId || !toAccountId) {
      return null;
    }

    const fromCurrency = this.accountCurrenciesValue[fromAccountId];
    const toCurrency = this.accountCurrenciesValue[toAccountId];

    if (!fromCurrency || !toCurrency) {
      return null;
    }

    return {
      fromCurrency,
      toCurrency,
      date,
    };
  }

  isCurrentExchangeRateState(fromCurrency, toCurrency, date) {
    if (!this.hasRequiredExchangeRateTargets()) {
      return false;
    }

    const currentFromAccountId = this.fromAccountTarget.value;
    const currentToAccountId = this.toAccountTarget.value;
    const currentFromCurrency =
      this.accountCurrenciesValue[currentFromAccountId];
    const currentToCurrency = this.accountCurrenciesValue[currentToAccountId];
    const currentDate = this.dateTarget.value;

    return (
      fromCurrency === currentFromCurrency &&
      toCurrency === currentToCurrency &&
      date === currentDate
    );
  }
}
