#!/usr/bin/env python3
"""Compile the native probe, deny its network, and sample RSS during playback."""
import json, subprocess, time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[4]
OUT=ROOT/'docs/verifications/mac-06'; BUILD=ROOT/'小说/client/build/mac06'
BUILD.mkdir(parents=True,exist_ok=True)
subprocess.run(['xcrun','swiftc',str(ROOT/'packages/platform_services/experiments/macos/SpeechProbe.swift'),'-o',str(BUILD/'speech-probe')],check=True)
started=time.monotonic()
with (BUILD/'speech-console.log').open('w') as log:
 process=subprocess.Popen(['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(BUILD/'speech-probe'),str(OUT/'tts-process-network-denied.json'),'600'],stdout=log,stderr=log)
 samples=[]
 while process.poll() is None:
  rss=subprocess.run(['/bin/ps','-o','rss=','-p',str(process.pid)],text=True,capture_output=True).stdout.strip()
  if rss.isdigit(): samples.append({'elapsed_seconds':round(time.monotonic()-started,2),'rss_kib':int(rss)})
  time.sleep(10)
 if process.returncode: raise SystemExit('speech probe failed; see local build log')
(OUT/'tts-memory.json').write_text(json.dumps({'scope':'probe process only; speech service/XPC memory excluded','samples':samples,'peak_rss_kib':max(s['rss_kib'] for s in samples)},indent=2)+'\n')
print('Completed 600-second volume-zero TTS probe with RSS samples.')
