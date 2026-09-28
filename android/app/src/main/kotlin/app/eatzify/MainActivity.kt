package app.eatzify

import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * A FRAGMENT activity, not the template's `FlutterActivity`. The `health` plugin asks Health Connect
 * for permission through `registerForActivityResult`, which needs a `ComponentActivity`; from a plain
 * `FlutterActivity` the request fails at the cast and the permission sheet never appears.
 */
class MainActivity : FlutterFragmentActivity()
