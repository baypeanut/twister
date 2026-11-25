#!/usr/bin/env python3
"""Generate disposable media, own a loopback server, and test the real Swift engine."""
from pathlib import Path
from functools import partial
import http.server, subprocess, threading, time
ROOT=Path(__file__).resolve().parent.parent
OUTPUT=ROOT/'build/web-download-integration'
SERVER=OUTPUT/'Server'
SERVER.mkdir(parents=True,exist_ok=True)
run=lambda args:subprocess.run([str(x) for x in args],cwd=ROOT,check=True)
ffmpeg=ROOT/'Tools/ffmpeg'
run([ffmpeg,'-y','-hide_banner','-loglevel','error','-f','lavfi','-i','testsrc2=size=320x180:rate=24','-f','lavfi','-i','sine=frequency=660:sample_rate=44100','-t','3','-c:v','libx264','-pix_fmt','yuv420p','-c:a','aac',SERVER/'Clip.mp4'])
run([ffmpeg,'-y','-hide_banner','-loglevel','error','-i',SERVER/'Clip.mp4','-frames:v','1',SERVER/'Picture.png'])
(SERVER/'index.html').write_text('<!doctype html><title>Twister test</title><video src="/Clip.mp4" controls></video>')
class Handler(http.server.SimpleHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_HEAD(self):
  if self.path in ['/Slow.mp4','/UnknownSlow.mp4']:
   self.send_response(200);self.send_header('Content-Type','video/mp4')
   if self.path=='/Slow.mp4':self.send_header('Content-Length','50000000')
   self.end_headers()
  else:super().do_HEAD()
 def do_GET(self):
  if self.path in ['/Slow.mp4','/UnknownSlow.mp4']:
   self.do_HEAD()
   try:
    for _ in range(1000):self.wfile.write(b'x'*50000);self.wfile.flush();time.sleep(.2)
   except (BrokenPipeError,ConnectionResetError):pass
  else:super().do_GET()
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),partial(Handler,directory=str(SERVER)))
worker=threading.Thread(target=server.serve_forever,daemon=True);worker.start()
try:
 run(['swift','build','-c','release','--product','Twister'])
 binary_dir=Path(subprocess.check_output(['swift','build','-c','release','--show-bin-path'],cwd=ROOT,text=True).strip())
 binary=OUTPUT/'verify-web-download'
 # SwiftPM's native build system keeps one object per source file and the
 # modules in Modules/; the Swift Build system links one TwisterCore.o and
 # keeps the module beside it.
 objects=sorted((binary_dir/'TwisterCore.build').glob('*.o')) or ([binary_dir/'TwisterCore.o'] if (binary_dir/'TwisterCore.o').is_file() else [])
 assert objects,'SwiftPM did not produce the core engine object files'
 modules=binary_dir/'Modules' if (binary_dir/'Modules/TwisterCore.swiftmodule').exists() else binary_dir
 assert (modules/'TwisterCore.swiftmodule').exists(),'SwiftPM did not produce the core engine module'
 run(['swiftc','-parse-as-library','-I',modules,*objects,ROOT/'scripts/verify-web-download.swift','-o',binary])
 run([binary,OUTPUT,f'http://127.0.0.1:{server.server_port}'])
finally:server.shutdown();server.server_close();worker.join()
