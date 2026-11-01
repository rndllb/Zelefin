package app.zelefin.client.ui

import android.content.res.Configuration

/**
 * Tablets, TVs, Chromebooks, and unfolded foldables: Zelefin turns with them and uses its wide
 * layout, as it does on iPad. Phones stay portrait. A 1080p TV is 960×540 dp, under the tablet
 * width, so it's matched by its UI mode instead.
 */
internal fun Configuration.isLargeScreen(): Boolean =
    smallestScreenWidthDp >= 600 ||
        (uiMode and Configuration.UI_MODE_TYPE_MASK) == Configuration.UI_MODE_TYPE_TELEVISION
