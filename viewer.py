import asyncio, json, sys, cv2, numpy as np, websockets

ip = sys.argv[1] if len(sys.argv) > 1 else input("IP del iPhone: ").strip()

def draw(img, v):
    h, w = img.shape[:2]
    for hand in v.get("hands", []):
        for x, y, c in hand["points"].values():
            cv2.circle(img, (int(x * w), int((1 - y) * h)), 4, (0, 255, 0), -1)
    for x, y, c in v.get("body", {}).values():
        cv2.circle(img, (int(x * w), int((1 - y) * h)), 5, (0, 165, 255), -1)

async def main():
    last = {"front": {}, "back": {}}
    async with websockets.connect(f"ws://{ip}:8080", max_size=None) as ws:
        async for msg in ws:
            if isinstance(msg, bytes):
                if msg[:4] == b"BACK":
                    src, data = "back", msg[4:]
                else:
                    src, data = "front", msg
                img = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
                if img is None:
                    continue
                draw(img, last[src])
                cv2.imshow("iPhone " + ("trasera" if src == "back" else "Face ID"), img)
                if cv2.waitKey(1) == 27:
                    break
            else:
                d = json.loads(msg)
                if "vision" in d:
                    v = d["vision"]
                    last[v.get("src", "front")] = v
                elif "blendshapes" in d:
                    print("jawOpen: %.2f" % d["blendshapes"].get("jawOpen", 0), end="\r")

asyncio.run(main())
