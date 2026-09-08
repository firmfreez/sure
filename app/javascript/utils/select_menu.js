// Mobile selectors expand in the form's normal flow. Discard desktop
// positioning after a viewport change, including any old height constraint.
export function resetInlineSelectPosition(menu) {
  if (getComputedStyle(menu).position !== "static") return false;

  for (const property of ["left", "right", "top", "bottom", "width", "max-height", "overflow-y"]) {
    menu.style.removeProperty(property);
  }
  return true;
}
