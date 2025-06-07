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
The `image_picker` package is used to select an image from the device, which is
encoded to base64 before advertising.

## BLE Advertising Example

For a guide on building a simple application that exchanges detailed sale announcements (title, description, price, image and phone number) via Bluetooth Low Energy, see [docs/ble_annonces_ble.md](docs/ble_annonces_ble.md).
