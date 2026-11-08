# Results runbook

This runbook covers the Results production: the lab results feed that the clinic reads every morning. It is written for whoever is on call.

## Rotating the certificate

The Results feed signs its messages with a TLS certificate that expires every year. Rotate it before the expiry date:

1. Open the Results production in the Management Portal and stop the item named Results.Sender.
2. Install the new certificate in the SSL configuration named ResultsClient, then restart the item and send one test result.
3. Check that the partner confirmed the test result, and write the new expiry date in the on-call log.

## Clearing the queue

When the Results queue grows and does not shrink, find the message at the head of the queue, read why it fails, fix the cause, and resend it. Do not delete a queued message unless the lab confirms that it is a duplicate.

## Restarting the Results production

Restart the production only in the maintenance window, after the item Results.Sender has finished its current message. Tell the lab before the restart and after it, and watch the queue for ten minutes.

## Contacting the lab

The lab's on-call desk answers at any hour. Give them the accession number of the result and the time of the failure, and write down the name of the person you spoke with.
