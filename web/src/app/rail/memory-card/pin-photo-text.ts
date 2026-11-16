/**
 * The notice for a pin that the server refuses with 409 `pin_photo` (Story 26.3, DW-1313): the memory is the caption of a photo. The sentence is the server's
 * (Web.Api MESSAGEPINPHOTO), copied here so that the page keeps its own texts. This module is loaded only when that refusal comes (a dynamic import from the Memory
 * card, DW-1282), so it stays out of the initial bundle.
 */
export const PIN_PHOTO_TEXT = "This memory came from a photo, so it can't be pinned.";
