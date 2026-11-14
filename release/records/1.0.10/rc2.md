# OcuTalon 1.0.10 rc2

## IPM artifact
Result: fail
Candidate: 1.0.10 rc2, release/1.0.10-rc2 at c7feff8bd86bc7fe52c84c3ee967f4daea59c380
Published: no; publishing to the package registry is the author's own action, outside this sequence

## Release sequence
Result: failed at ipm: the package did not install: IPM could not be loaded: Instance is not running
Mode: release
Candidate: 1.0.10 rc2, release/1.0.10-rc2 at c7feff8bd86bc7fe52c84c3ee967f4daea59c380
Cut from: release/1.0.10-rc1 at 2eb1f6bb6e44b3770031d6932cb30a986457112b, then af212d21b860e1396f5498a0957a02f8bdb450a7 293b98d3293460848b02c3c96654c0d5a5c9392e cherry-picked from rc-base/1.0.10
Hands-on time: 0 s for this candidate; 0 s for 1.0.10 so far (target at most 15 min; CI and the hands-on pass not counted)
Run: 2026-11-14T22:59:23Z to 2026-11-14T23:33:26Z

| Step | Result | Detail |
| --- | --- | --- |
| cut | pass | module.xml and src/module.xml set to 1.0.10; web bundle built with Node.js and committed; fixes cherry-picked: 2 |
| image | pass | /opt/ocutalon/version reads 1.0.10 in the image built from the candidate |
| overview | pass | the generated sections equal a fresh generation from the candidate, and the overview tests pass |
| ipm | fail | the package did not install: IPM could not be loaded: Instance is not running |
| record | committed, not pushed | the author's word was not given |
