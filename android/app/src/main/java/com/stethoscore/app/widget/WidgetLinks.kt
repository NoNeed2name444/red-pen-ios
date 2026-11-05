package com.stethoscore.app.widget

import android.content.Context
import android.content.Intent
import android.net.Uri
import com.stethoscore.app.AppLink
import com.stethoscore.app.MainActivity

/**
 * The intent a widget's tap starts: the app's own link (AppLink.url) as a VIEW
 * on MainActivity. SINGLE_TOP with CLEAR_TOP brings back the activity already
 * open, so its onNewIntent takes the link (AppLinks.pending) instead of a
 * second activity starting over it; launchMode stays standard. Tested in
 * WidgetLinksTest.
 */
object WidgetLinks {
    const val flags: Int = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP

    fun intent(context: Context, link: AppLink): Intent =
        Intent(Intent.ACTION_VIEW, Uri.parse(link.url))
            .setClass(context, MainActivity::class.java)
            .addFlags(flags)
}
