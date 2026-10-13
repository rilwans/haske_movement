import 'package:geolocator/geolocator.dart';

/// Where the canvasser is, if the phone can tell within a few seconds. GPS
/// works with no internet; a visit is saved without it when it can't.
Future<Position?> currentPosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return null;
    }
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(timeLimit: Duration(seconds: 10)),
    ).catchError((_) => Geolocator.getLastKnownPosition().then((p) => p!));
  } catch (_) {
    return null;
  }
}
