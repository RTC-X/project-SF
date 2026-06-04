import os
from playwright.sync_api import sync_playwright

def render():
    html_content = """<!DOCTYPE html>
<html>
<head>
<style>
  html, body {
    margin: 0;
    padding: 0;
    width: 512px;
    height: 512px;
    background: transparent;
    overflow: hidden;
  }
</style>
</head>
<body>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512" style="display: block;">
  <defs>
    <linearGradient id="g" x1="0%" y1="100%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#e87b24" />
      <stop offset="100%" stop-color="#3dcbb0" />
    </linearGradient>
  </defs>
  <rect width="512" height="512" rx="144" fill="url(#g)" />
  <path d="M 144 160 L 224 240 L 144 320" stroke="white" stroke-width="40" stroke-linecap="butt" stroke-linejoin="miter" fill="none" />
  <path d="M 256 336 H 368" stroke="white" stroke-width="40" stroke-linecap="butt" fill="none" />
</svg>
</body>
</html>"""

    temp_html = "temp_logo.html"
    with open(temp_html, "w", encoding="utf-8") as f:
        f.write(html_content)

    try:
        with sync_playwright() as p:
            browser = p.chromium.launch()
            page = browser.new_page(viewport={"width": 512, "height": 512})
            page.goto(f"file://{os.path.abspath(temp_html)}")
            page.screenshot(path="scripts/c2_logo.png", omit_background=True)
            browser.close()
        print("Logo regenerated successfully!")
    finally:
        if os.path.exists(temp_html):
            os.remove(temp_html)

if __name__ == "__main__":
    render()
