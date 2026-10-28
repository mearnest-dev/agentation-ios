#!/usr/bin/env python3
"""Records a shareable demo video of the demo app.

Runs DemoRecordingTests in the booted Simulator while recording the screen, then
composites a 1080x1920 MP4 with captions and tap circles.

Usage (from Demo/):  python3 scripts/record-demo.py [output.mp4]
Needs: xcodegen, ffmpeg. Start `npx -y agentation-mcp server` first for a green sync dot.
"""
import json, os, signal, subprocess, sys, tempfile, time

DEMO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "agentation-ios-demo.mp4")
WORK = tempfile.mkdtemp(prefix="agentation-demo-")
BUNDLE = "dev.mearnest.AgentationDemo"
SCALE = 3                      # Simulator points -> recording pixels
PHONE_W, PHONE_H = 718, 1562   # phone size in the final frame
PHONE_X, PHONE_Y = (1080 - PHONE_W) // 2, 215


def run(*cmd, **kw):
    print("+", " ".join(cmd))
    return subprocess.run(cmd, check=True, **kw)


def booted_udid():
    devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "booted", "-j"]))
    for runtime in devices["devices"].values():
        for device in runtime:
            if device["state"] == "Booted":
                return device["udid"]
    sys.exit("Boot a Simulator first.")


udid = booted_udid()
derived = os.path.join(WORK, "dd")
os.chdir(DEMO)
run("xcodegen", "-q")
run("xcodebuild", "build-for-testing", "-quiet", "-project", "AgentationDemo.xcodeproj", "-scheme", "AgentationDemo",
    "-destination", f"id={udid}", "-derivedDataPath", derived)
subprocess.run(["xcrun", "simctl", "uninstall", udid, BUNDLE])
run("xcrun", "simctl", "status_bar", udid, "override", "--time", "9:41", "--batteryState", "charged",
    "--batteryLevel", "100", "--wifiBars", "3", "--cellularBars", "4")

raw = os.path.join(WORK, "raw.mp4")
events_path = os.path.join(WORK, "events.json")
recorder = subprocess.Popen(["xcrun", "simctl", "io", udid, "recordVideo", "--codec", "h264", "--force", raw],
                            stderr=subprocess.PIPE, text=True)
for line in recorder.stderr:
    if "Recording started" in line:
        break
record_start = time.time()

env = dict(os.environ, TEST_RUNNER_DEMO_EVENTS=events_path)
try:
    run("xcodebuild", "test-without-building", "-quiet", "-project", "AgentationDemo.xcodeproj",
        "-scheme", "AgentationDemo", "-destination", f"id={udid}", "-derivedDataPath", derived,
        "-only-testing:AgentationDemoUITests/DemoRecordingTests", env=env)
finally:
    recorder.send_signal(signal.SIGINT)
    recorder.wait()
    subprocess.run(["xcrun", "simctl", "status_bar", udid, "clear"])

json.dump({"t": record_start}, open(os.path.join(WORK, "record_start.json"), "w"))
events = json.load(open(events_path))
for e in events:
    e["t"] -= record_start      # seconds into the raw recording
start = events[0]["t"] - 2.0    # a beat before the first tap
end = events[-1]["t"] + 2.4     # let the last toast show

# Tap circles: a dot for taps, a moving dot for the drag.
taps = [e for e in events if e["kind"] in (0, 1, 2)]
dots = []
i = 0
while i < len(taps):
    e = taps[i]
    if e["kind"] == 1 and i + 1 < len(taps):
        e2 = taps[i + 1]
        t, t2 = e["t"], e2["t"]
        progress = f"min(max((t-{t:.3f})/{t2 - t:.3f},0),1)"
        x = f"{e['x'] * SCALE - 75}+({(e2['x'] - e['x']) * SCALE})*{progress}"
        y = f"{e['y'] * SCALE - 75}+({(e2['y'] - e['y']) * SCALE})*{progress}"
        dots.append((x, y, t - 0.05, t2 + 0.25))
        i += 2
    else:
        dots.append((str(e["x"] * SCALE - 75), str(e["y"] * SCALE - 75), e["t"] - 0.05, e["t"] + 0.35))
        i += 1

# Segments of the raw recording: real time around each action, fast-forward through the waits.
FAST = 3.0
normal = []
for n, e in enumerate(events):
    if e["kind"] == 3:
        normal.append((e["t"], events[n + 1]["t"] + 0.5))           # typing
    elif e["kind"] in (0, 1, 2):
        gap = (events[n + 1]["t"] - e["t"]) if n + 1 < len(events) else 0
        hold = 2.4 if gap > 4.5 else 1.0                          # linger on the inspect panel
        normal.append((e["t"] - 0.2, e["t"] + hold))
normal.append((events[-1]["t"], end))
normal.sort()
merged = []
for a, b in normal:
    if merged and a <= merged[-1][1]:
        merged[-1] = (merged[-1][0], max(merged[-1][1], b))
    else:
        merged.append((max(a, start), b))
segments, cursor = [], start
for a, b in merged:
    if a > cursor:
        segments.append((cursor, a, FAST))
    segments.append((a, b, 1.0))
    cursor = b
duration = sum((b - a) / speed for a, b, speed in segments)

# fps=30 first so stretches with no screen updates still have frames at the right times.
filters = ["[0:v]fps=30[v0]",
           f"[1:v]split={len(dots)}" + "".join(f"[d{n}]" for n in range(len(dots)))]
for n, (x, y, a, b) in enumerate(dots):
    filters.append(f"[v{n}][d{n}]overlay=x='{x}':y='{y}':enable='between(t,{a:.3f},{b:.3f})'[v{n + 1}]")
filters.append(f"[v{len(dots)}]split={len(segments)}" + "".join(f"[s{n}]" for n in range(len(segments))))
for n, (a, b, speed) in enumerate(segments):
    filters.append(f"[s{n}]trim=start={a:.3f}:end={b:.3f},setpts=(PTS-STARTPTS)/{speed}[c{n}]")
filters.append("".join(f"[c{n}]" for n in range(len(segments))) + f"concat=n={len(segments)}:v=1:a=0[timed]")
filters += [f"[timed]scale={PHONE_W}:{PHONE_H}:flags=lanczos,format=rgba[phone]",
            "[2:v]format=gray[mask]",
            "[phone][mask]alphamerge[rounded]",
            f"[3:v][rounded]overlay={PHONE_X}:{PHONE_Y}:shortest=1,format=yuv420p[out]"]

run("swift", os.path.join(DEMO, "scripts", "demo-assets.swift"), WORK, str(PHONE_W), str(PHONE_H))
run("ffmpeg", "-y", "-loglevel", "error",
    "-i", raw,
    "-loop", "1", "-i", os.path.join(WORK, "tap.png"),
    "-loop", "1", "-i", os.path.join(WORK, "mask.png"),
    "-loop", "1", "-i", os.path.join(WORK, "background.png"),
    "-filter_complex", ";".join(filters), "-map", "[out]", "-t", f"{duration:.3f}",
    "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-r", "30", "-movflags", "+faststart", OUT)
print(f"Saved {OUT} ({duration:.1f}s). Work files: {WORK}")
