# xchange

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Updating dependencies

After cloning the repository, run `flutter pub get` to install the latest
packages. The project now relies on `flutter_local_notifications` 19.2.1 to
avoid compilation issues on recent Android versions. The `permission_handler`
package is used to request runtime Bluetooth permissions. Location permission is
only requested on Android versions prior to 12.
Local photos can be selected using the `image_picker` package so that they are
served via Bluetooth without requiring an external URL.
Wi‑Fi Direct support is implemented with the `flutter_p2p_connection` plugin so
that a voice call can be initiated even without an access point. Before
creating a Wi‑Fi Direct group, call `askP2pPermissions()` from the plugin to
request the required `ACCESS_FINE_LOCATION`, `CHANGE_WIFI_STATE` and
`NEARBY_WIFI_DEVICES` permissions on recent Android versions.

## BLE Advertising Example

For a guide on building a simple application that exchanges detailed sale announcements (title, description, price and image) via Bluetooth Low Energy, see [docs/ble_annonces_ble.md](docs/ble_annonces_ble.md).

The application now includes a Bluetooth connection that fetches the advertised photo using a custom GATT service. Once connected, a peer‑to‑peer voice call can be started over Wi‑Fi using WebRTC. The call relies on the broadcaster's local IP address which may come from a standard network or a Wi‑Fi Direct group so an access point is not required.
