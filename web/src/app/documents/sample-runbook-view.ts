/**
 * The sample runbook of the Documents page and the demo guide (Story 20.3; EXPERIENCE: Step 3, memory and documents, and Demo guide and
 * controls; FR-42). A framework-free module: it imports nothing and uses only erasable TypeScript syntax, so Node runs it as it is.
 *
 * - SAMPLE_RUNBOOK_TEXTS.name is the file name the sample is added under; a chip names the document without its `.md`.
 * - SAMPLE_RUNBOOK_TEXTS.text is the runbook, ASCII only and ending in one newline. It is a constant of the web bundle: nothing is fetched.
 *   Its `## ` lines open the sections that a chip names, and each section is under 1,000 characters, so each is one passage. Its facts are
 *   the demo's own: the items of the Orders production (OcuTalon.Demo.Orders.Production) and the error of the order date (Transform).
 * - SAMPLE_RUNBOOK_TEXTS.question is the question that item 6 of More to try suggests, which the sample's section "When orders fail with a
 *   date error" answers.
 */

/** The ruled texts of the sample runbook (Story 20.3, Planner ruling 2026-11-09), word for word. */
export const SAMPLE_RUNBOOK_TEXTS = {
  name: 'Sample runbook.md',
  text: `# Sample runbook: the demo's Orders feed

This sample comes with OcuTalon's web app. It covers the Orders production that the demo runs in namespace OCUORDERS, where a simulated partner sends orders.

## How orders flow

The partner's orders arrive at PartnerOrdersIn. OrdersFromPartner turns each order into a warehouse order, and OrdersToWarehouse takes the orders that pass. Each order has a number such as PO-0001, an item and a quantity.

## When orders fail with a date error

OrdersFromPartner accepts an order date written YYYY-MM-DD and nothing else. When the partner sends dates in another format, such as MM/DD/YYYY, each of those orders fails with "The order date was not in the expected format." Break the feed plays this out with 50 orders.

1. Read the error of one failed order to see the format the partner sent.
2. Rewrite each failed order's date as YYYY-MM-DD and resend it.
3. Check how many orders went through to OrdersToWarehouse.

Then ask the partner to go back to YYYY-MM-DD, so that the next batch does not fail.

## When the Results partner changes its certificate

The Results partner gives notice before the TLS certificate on its results endpoint changes. Load the new certificate before the change, so that results keep flowing.
`,
  question: 'According to the runbook, what should I do when partner orders fail with a date error?',
} as const;
