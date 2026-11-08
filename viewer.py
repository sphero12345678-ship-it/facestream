import asyncio, json, sys, cv2, numpy as np, websockets

async def main(ip):
    async with websockets.connect(f"ws://{ip}:8080", max_size=None) as ws:
        async for msg in ws:
            if isinstance(msg, bytes):
                img = cv2.imdecode(np.frombuffer(msg, np.uint8), cv2.IMREAD_COLOR)
                cv2.imshow("iPhone", img)
                if cv2.waitKey(1) == 27:
                    break
            else:
                d = json.loads(msg)
                if "blendshapes" in d:
                    print("jawOpen: %.2f" % d["blendshapes"].get("jawOpen", 0), end="\r")

asyncio.run(main(sys.argv[1]))
