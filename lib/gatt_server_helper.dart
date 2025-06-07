import 'dart:convert';
import 'dart:typed_data';

import 'package:ble_gatt_server/ble_gatt_server.dart';

import 'models/announcement.dart';

class GattServerHelper {
  static const serviceUuid = '0000abcd-0000-1000-8000-00805f9b34fb';
  static const adCharUuid = '0000abcd-0001-1000-8000-00805f9b34fb';
  static const imageCharUuid = '0000abcd-0002-1000-8000-00805f9b34fb';

  final BleGattServer _server = BleGattServer();
  final Map<String, Uint8List?> _values = {};

  Future<void> start(Announcement ad, Uint8List? imageBytes) async {
    final adChar = BleGattCharacteristic(
      uuid: adCharUuid,
      properties: BleGattCharacteristic.PROPERTY_READ,
      permissions: BleGattCharacteristic.PERMISSION_READ,
      descriptors: [],
    );
    final imgChar = BleGattCharacteristic(
      uuid: imageCharUuid,
      properties: BleGattCharacteristic.PROPERTY_READ,
      permissions: BleGattCharacteristic.PERMISSION_READ,
      descriptors: [],
    );

    _values[adChar.uuid] =
        Uint8List.fromList(utf8.encode(jsonEncode(ad.toJson())));
    _values[imgChar.uuid] = imageBytes;

    await _server.startServer();
    await _server.addService(
      BleGattService(
        uuid: serviceUuid,
        serviceType: BleGattService.SERVICE_TYPE_PRIMARY,
        characteristics: [adChar, imgChar],
      ),
    );

    _server.handleEvents(
      onCharacteristicReadRequest:
          (device, requestId, offset, characteristic) async {
        final data = _values[characteristic?.uuid] ?? Uint8List(0);
        await _server.sendResponse(
            device!, requestId, BleGattServer.GATT_SUCCESS, offset, data);
      },
    );
  }

  Future<void> stop() => _server.stopServer();
}
