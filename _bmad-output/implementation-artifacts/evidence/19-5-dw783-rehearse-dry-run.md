# Story 19.5, DW-783: the rehearsal dry run with the network cut and joined again

Run 2026-11-08 on a lane-C throwaway (run tag e19s5ir, the lane's variables, web port 52803, the CI mock, no key) with the tree of this story and no change to
any file of `release/rehearse.sh`: `release/rehearse.sh install --dry-run --rc 1 --record <file outside the repository>`, then `report` and `down`.

The install steps, as the script printed them:

| Step | Result | Detail |
|------|--------|--------|
| hosts | pass | both hosts answered; git and Docker on the clean host, no OcuTalon container or volume |
| copy | pass | git bundle of 31,234 KiB; the clone is at the candidate commit |
| install | pass | install.sh reached ready; first start 107 s, install included |
| memory-offline | pass | with every network of the iris container disconnected, `OcuTalon.Test.Memory.Offline` passed (3 test methods, none skipped); the networks are connected again |
| sign-in | pass | the driver host signed in at the printed address as the printed user |

What the three facts of the task show:

- `MEMOFF-RECONNECTED`: the step `memory-offline` passes only when the remote command printed `MEMOFF-RECONNECTED` (and no `MEMOFF-CONNECT-FAILED`), so the
  `pass memory-offline ... the networks are connected again` line above is that line, read by the script (`release/rehearse.sh:1159` prints it, `:1167` requires it). The step also needs
  `MEMOFF-NET-DOWN` (a name lookup failed while the networks were cut) and the memory test passing with none skipped.
- The `sign-in` step ran right after the reconnect and passed: the driver host signed in at `http://127.0.0.1:52803`, the published web port, and the page held
  `<app-root`.
- `docker port` of the iris container after the reconnect (the container `ocutalon-rehearse-e19s5ir-...-iris-1`, read before `down`): `52773/tcp -> 127.0.0.1:52803`.
  The published port survived the disconnect and the connect.

`report` ended `RESULT dry run` (a dry run is never a pass) and `down` removed the project, its volume and the state. No failure, so no `intent gap` on
`release/rehearse.sh:1159`; DW-783 needs no hunk in a release tool.
