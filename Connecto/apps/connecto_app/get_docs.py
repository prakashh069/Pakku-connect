import urllib.request
from bs4 import BeautifulSoup
import re

url = "https://developer.android.com/about/versions/14/changes/fgs-types-required"
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
try:
    html = urllib.request.urlopen(req).read()
    soup = BeautifulSoup(html, 'html.parser')
    for h3 in soup.find_all('h3'):
        if "connected device" in h3.text.lower() or "data sync" in h3.text.lower():
            print("---", h3.text)
            elem = h3.find_next_sibling()
            while elem and elem.name != 'h3':
                print(re.sub(r'\s+', ' ', elem.get_text()).strip())
                elem = elem.find_next_sibling()
except Exception as e:
    print(e)
