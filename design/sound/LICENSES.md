# Sounds in the app

| Asset | Source | Author | Licence |
|---|---|---|---|
| `ios/RedPen/Assets.xcassets/Heartbeat.dataset/heartbeat.caf` (the opening's lub-dub) | Synthesised by `tools/make_heartbeat.py` from arithmetic alone (damped valve tones, band-limited noise, a chest-and-tubing filter); no recording or sample was used | Stethoscore (this repository) | Owned outright; no third-party terms |

A recorded heartbeat under CC0 was looked for first (Wikimedia Commons);
its search could not be reached from the build machine at the time, so the
sound was made instead, which leaves no licence to keep track of. To
regenerate it: `python3 tools/make_heartbeat.py`, then put the S1 and S2
onsets it prints into `HeartbeatSound` (ios/RedPen/Shared/LaunchOpening.swift);
the launchopening suite checks they match the file.
