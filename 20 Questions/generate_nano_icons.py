#!/usr/bin/env python3
import base64
import csv
import os
import pathlib
import time
import requests

# Configuration
API_KEY = os.environ.get("NANO_BANANA_API_KEY", "AIzaSyDs1O6_ro7ljcJ1ceXt_hJY8PY4cFmnAX8")
ENDPOINT = "https://api.nanobananaapi.ai/api/v1/nanobanana/generate"
STATUS_ENDPOINT = "https://api.nanobananaapi.ai/api/v1/nanobanana/record-info"
CALLBACK_URL = os.environ.get("NANO_BANANA_CALLBACK", "https://your-callback-url.com/webhook")
OUT_DIR = pathlib.Path("generated_avatars")

STYLE_BLOCK = (
    "Flat vector icon, filled shapes, bold clean outlines, rounded proportions, "
    "minimal/no background, centered subject, 1:1 aspect, palette: pastel teal, "
    "peach, lilac accents. No text."
)


def load_animals(csv_path="animals_20q.csv"):
    with open(csv_path, newline="") as f:
        reader = csv.reader(f)
        next(reader, None)  # header
        for row in reader:
            if not row or not row[0].strip():
                continue
            yield row[0].strip()


def generate(animal: str):
    prompt = f"{STYLE_BLOCK} Icon of a {animal}."
    r = requests.post(
        ENDPOINT,
        headers={"Authorization": f"Bearer {API_KEY}"},
        json={
            "prompt": prompt,
            "type": "TEXTTOIMAGE",
            "numImages": 1,
            "image_size": "1:1",
            "callBackUrl": CALLBACK_URL,
        },
        timeout=60,
    )
    r.raise_for_status()
    task_id = r.json()["data"]["taskId"]

    # Poll until the task completes.
    while True:
        s = requests.get(
            STATUS_ENDPOINT,
            headers={"Authorization": f"Bearer {API_KEY}"},
            params={"taskId": task_id},
            timeout=60,
        )
        s.raise_for_status()
        data = s.json()["data"]
        flag = data.get("successFlag")
        if flag == 1:
            url = data["response"]["resultImageUrl"]
            img = requests.get(url, timeout=60)
            img.raise_for_status()
            OUT_DIR.mkdir(exist_ok=True)
            out_path = OUT_DIR / f"{animal.lower().replace(' ', '_')}.png"
            out_path.write_bytes(img.content)
            print(f"Saved {out_path}")
            return
        elif flag in (2, 3):
            raise RuntimeError(f"Task failed for {animal}: {data.get('errorMessage')}")
        time.sleep(1.0)


def main():
    for animal in load_animals():
        try:
            generate(animal)
        except Exception as exc:
            print(f"Failed {animal}: {exc}")


if __name__ == "__main__":
    main()
