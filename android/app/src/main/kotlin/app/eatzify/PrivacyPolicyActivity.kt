package app.eatzify

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle

/**
 * Where Health Connect sends someone who taps "privacy policy" on Eatzify's permission screen.
 *
 * Its own tiny activity rather than [MainActivity]: that one boots Flutter, signs in and syncs,
 * none of which a person asking "what will this app do with my steps?" wants to sit through. This
 * opens the policy in the browser and gets out of the way. Google app review follows this link
 * before approving health permissions.
 */
class PrivacyPolicyActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(getString(R.string.privacy_policy_url))))
        } catch (_: ActivityNotFoundException) {
            // No browser on the phone. There is nothing else to offer from a permission screen.
        }
        finish()
    }
}
