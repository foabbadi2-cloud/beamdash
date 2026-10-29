# BeamDash
Telemetry dashboard for BeamNG.drive (OutGauge UDP) with a CarPlay-style "Car" mode. Flutter: iOS, iPadOS, Android.

## Run
    flutter create . --platforms=ios,android   # generates native folders once
    flutter pub get && flutter run

Android: add `<uses-permission android:name="android.permission.INTERNET"/>`.
iOS: add `NSLocalNetworkUsageDescription` to Info.plist, and `LSApplicationQueriesSchemes` = spotify, tel, sms.

## Connect
BeamNG: Options > Other > OutGauge support ON, IP = device IP shown in Setup tab, port 4444.
PC works today. PS5: no public telemetry output was found, so use Demo mode until BeamNG documents one.

## Cars
Edit `assets/cars.json`. `real` mappings are community/lookalike guesses (`verified:false`), so check them.
OutGauge `car` field is a 4-char code, matched by prefix; unmatched cars fall back to the manual picker.
