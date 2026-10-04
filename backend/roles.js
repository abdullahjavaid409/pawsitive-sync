/**
 * Household roles. The server is the only place a role is enforced; the app
 * only hides what it knows the member can't do.
 *
 *  owner     — everything (billing, invites, sitter links, archive, members)
 *  caregiver — log/skip doses, refill, care events, add/edit pets & medicines, photos
 *  sitter    — view and log doses only
 */
export const roles = ["owner", "caregiver", "sitter"];

const everyone = ["owner", "caregiver", "sitter"];
const editors = ["owner", "caregiver"];
const ownerOnly = ["owner"];

/** Action → roles allowed. Every authenticated /v1 route maps to one of these. */
export const rules = Object.freeze({
  "household.read": everyone,
  "dose.log": everyone,
  "device.register": everyone,
  "member.leave": everyone,
  "account.delete": everyone,
  // A caregiver or sitter who pays shares their own Pro with the household.
  "billing.refresh": everyone,
  "pet.add": editors,
  "pet.update": editors,
  "pet.photo": editors,
  "medication.add": editors,
  "medication.update": editors,
  "medication.refill": editors,
  "careEvent.add": editors,
  "careEvent.remove": editors,
  "export": editors,
  "medication.archive": ownerOnly,
  "invite.rotate": ownerOnly,
  "sitterLinks.manage": ownerOnly,
  "members.manage": ownerOnly,
  "billing.plan": ownerOnly,
  "apple.link": ownerOnly,
});

/** Outbox operation type → action, for /v1/sync/batch. */
export const batchActions = Object.freeze({
  logDose: "dose.log",
  addPet: "pet.add",
  updatePet: "pet.update",
  addMedication: "medication.add",
  updateMedication: "medication.update",
  removeMedication: "medication.archive",
  refill: "medication.refill",
  addCareEvent: "careEvent.add",
  removeCareEvent: "careEvent.remove",
});

export const ownerOnlyMessage = "Only the household owner can do that.";
export const sitterMessage = "Sitters can view and log doses only. Ask the owner for more access.";

/**
 * 403 for a role that can't do an action. `expose` lets the server send the
 * message as-is; `publicCode` tells newer apps it was a role (not Pro) problem.
 */
export class ForbiddenError extends Error {
  constructor(message, detail = message) {
    super(message);
    this.status = 403;
    this.expose = true;
    this.publicCode = "role_forbidden";
    this.detail = detail;
  }
}

/** True when `role` may do `action`. An unknown role gets sitter rights only. */
export function can(role, action) {
  const allowed = rules[action];
  if (!allowed) return false;
  return allowed.includes(roles.includes(role) ? role : "sitter");
}

/** Throws [ForbiddenError] unless `auth.role` may do `action`. */
export function requireRole(auth, action) {
  if (can(auth?.role, action)) return;
  const allowed = rules[action] ?? [];
  const message = allowed.length === 1 ? ownerOnlyMessage : sitterMessage;
  throw new ForbiddenError(message, `role ${auth?.role ?? "none"} cannot ${action}`);
}
