# Story 34.3 upload reset check (DW-754)

Measured 2026-11-05 by the Epic 34 runner (lane C), evidence for DW-754 and the spine's AD-25 union.

**What this shows.** On a throwaway online demo (the CI override and the test start values of docker/tests/lib-online.sh), a golden copy of the durable volume captured after a fresh start holds no `OcuTalon.Data.Upload` row and no `^OcuTalonP.UploadD`, `UploadI` or `UploadS` node; uploads added afterwards are gone after the golden copy is restored. The demo host's real reset scripts live outside this repository, so this emulates the restore that AD-25 documents (stop IRIS, replace the durable volume with the golden copy, start): that the host does the same is an inference, not measured here.

**Steps** (the project name is a throwaway; the golden volume is a copy of the durable volume at /durable, made and restored with `cp -a` as root from the project's own image):

- build and first start (at 0 s)
- the first start is ready (at 227 s)
- golden copy: stop, copy ocutalon-upload-reset-e34s3r-1793910804-56369_durable to ocutalon-upload-reset-e34s3r-1793910804-56369_golden (at 229 s)
- ready again after the golden copy (at 265 s)
- GET /v1/documents as the demo account (at 267 s)
- reset: stop, restore ocutalon-upload-reset-e34s3r-1793910804-56369_golden into ocutalon-upload-reset-e34s3r-1793910804-56369_durable (at 269 s)
- ready after the restore (at 294 s)
- done (at 296 s)

**CHK lines** (the IRIS session of the unit, namespace OCUTALON; the private database is the one under /durable/iris/mgr/ocutalon_private/):

```
CHK|dest|^/durable/iris/mgr/ocutalon_private/
CHK|rows|0
CHK|nodes|0
CHK|put|1|1
CHK|rows|2
CHK|get|200
CHK|aged|0
CHK|fresh|1
CHK|rows|0
CHK|data|0
CHK|index|0
CHK|stream|0
```

**Result.** 296 s in all; failed checks: 0. The route's sweep (the GET above, over real HTTP as the demo account) deleted the upload made two hours ago and kept the fresh one.
