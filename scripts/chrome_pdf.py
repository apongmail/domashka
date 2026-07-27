#!/usr/bin/env python3
"""Друк HTML у PDF через Chrome headless + CDP, з номером сторінки внизу по центру."""
import base64, json, pathlib, subprocess, sys, tempfile, time, urllib.request

import websocket

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

def main(html_path, pdf_path):
    profile = tempfile.mkdtemp(prefix="chrome-cdp-")
    proc = subprocess.Popen(
        [CHROME, "--headless", "--remote-debugging-port=0",
         "--remote-allow-origins=*",
         f"--user-data-dir={profile}", "--no-first-run", "about:blank"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        port_file = pathlib.Path(profile) / "DevToolsActivePort"
        for _ in range(100):
            if port_file.exists() and port_file.read_text().strip():
                break
            time.sleep(0.1)
        port = int(port_file.read_text().splitlines()[0])

        url = "file://" + str(pathlib.Path(html_path).resolve())
        req = urllib.request.Request(
            f"http://127.0.0.1:{port}/json/new?{urllib.parse.quote(url, safe='')}",
            method="PUT")
        target = json.load(urllib.request.urlopen(req))
        ws = websocket.create_connection(target["webSocketDebuggerUrl"], timeout=60)

        def call(method, params=None, _id=[0]):
            _id[0] += 1
            ws.send(json.dumps({"id": _id[0], "method": method, "params": params or {}}))
            while True:
                msg = json.loads(ws.recv())
                if msg.get("id") == _id[0]:
                    return msg.get("result", {})

        call("Page.enable")
        time.sleep(3)  # дочекатись рендеру (шрифти, вбудовані картинки)
        footer = ('<div style="width:100%;text-align:center;'
                  'font-size:9px;color:#8a94a0;font-family:Helvetica,Arial,sans-serif">'
                  '<span class="pageNumber"></span></div>')
        result = call("Page.printToPDF", {
            "printBackground": True,
            "displayHeaderFooter": True,
            "headerTemplate": "<span></span>",
            "footerTemplate": footer,
            "marginTop": 0.45, "marginBottom": 0.6,
            "marginLeft": 0.4, "marginRight": 0.4,
        })
        pathlib.Path(pdf_path).write_bytes(base64.b64decode(result["data"]))
        print(f"written {pdf_path} ({len(result['data'])*3//4} bytes)")
    finally:
        proc.terminate()

if __name__ == "__main__":
    import urllib.parse
    main(sys.argv[1], sys.argv[2])
