# OcuTalon 1.0.10 rc1

## Release sequence
Result: failed at overview: FAIL the first start did not end ready within 510 s
Mode: release
Candidate: 1.0.10 rc1, release/1.0.10-rc1 at 2eb1f6bb6e44b3770031d6932cb30a986457112b
Cut from: rc-base/1.0.10 at a6821f1d42843b96acf02fdb984871241ebf9710
Hands-on time: 0 s for this candidate; 0 s for 1.0.10 so far (target at most 15 min; CI and the hands-on pass not counted)
Run: 2026-11-14T22:17:13Z to 2026-11-14T22:29:02Z

| Step | Result | Detail |
| --- | --- | --- |
| cut | pass | module.xml and src/module.xml set to 1.0.10; web bundle built with Node.js and committed |
| image | pass | /opt/ocutalon/version reads 1.0.10 in the image built from the candidate |
| overview | fail | FAIL the first start did not end ready within 510 s |
| record | committed, not pushed | the author's word was not given |
