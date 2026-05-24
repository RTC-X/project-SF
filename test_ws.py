import asyncio, websockets, json
async def test():
    try:
        async with websockets.connect('wss://c2scripts.xyz/ws/c2/') as ws:
            print('Connected!')
            await ws.send(json.dumps({'action': 'register', 'username': 'TestBot', 'api_key': 'fake_key'}))
            response = await ws.recv()
            print('Received:', response)
    except Exception as e:
        print('Error:', e)
asyncio.run(test())
