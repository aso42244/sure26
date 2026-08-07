import { Controller } from "@hotwired/stimulus"

// Collapsible budget "folder": toggles the visibility of a folder's child
// budget rows and remembers the collapsed state per browser (localStorage),
// keyed by the folder's category id so it survives reloads and Turbo renders.
//
// Connects to data-controller="budget-folder"
export default class extends Controller {
  static targets = ["children", "chevron"]
  static values = { key: String }

  connect() {
    this.apply(this.collapsed)
  }

  toggle() {
    const next = !this.collapsed
    this.collapsed = next
    this.apply(next)
  }

  apply(collapsed) {
    if (this.hasChildrenTarget) {
      this.childrenTarget.classList.toggle("hidden", collapsed)
    }
    if (this.hasChevronTarget) {
      // point right when collapsed, down when expanded
      this.chevronTarget.classList.toggle("-rotate-90", collapsed)
    }
  }

  get storageKey() {
    return `budget-folder:${this.keyValue}`
  }

  get collapsed() {
    try {
      return window.localStorage.getItem(this.storageKey) === "1"
    } catch (e) {
      return false
    }
  }

  set collapsed(value) {
    try {
      window.localStorage.setItem(this.storageKey, value ? "1" : "0")
    } catch (e) {
      // localStorage unavailable (private mode); collapse is session-only
    }
  }
}
