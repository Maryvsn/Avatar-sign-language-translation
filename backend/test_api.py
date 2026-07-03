import requests
import urllib.parse

# 1) Get available signs first  
r = requests.get("http://127.0.0.1:8000/available-signs")
data = r.json()
print("Total signs:", data["count"])

# Pick the first word and properly encode it
word = data["signs"][0]
print("Testing word:", repr(word))

# 2) Test text-to-sign with proper encoding
encoded_word = urllib.parse.quote(word)
url = "http://127.0.0.1:8000/text-to-sign?word=" + encoded_word
print("URL:", url)

r = requests.post(url)
print("Status:", r.status_code)
print("Content-Type:", r.headers.get("content-type"))
print("Response size:", len(r.content), "bytes")

if r.headers.get("content-type") == "image/gif":
    with open("test_output.gif", "wb") as f:
        f.write(r.content)
    print("SUCCESS! GIF saved to test_output.gif")
else:
    print("Response:", r.text[:500])
