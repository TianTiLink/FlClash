package com.follow.clash.common

import android.content.ComponentName

object Components {
    const val PACKAGE_NAME = "com.tiantilink.app"

    val MAIN_ACTIVITY =
        ComponentName(GlobalState.packageName, "com.follow.clash.MainActivity")

    val TEMP_ACTIVITY =
        ComponentName(GlobalState.packageName, "com.follow.clash.TempActivity")

    val BROADCAST_RECEIVER =
        ComponentName(GlobalState.packageName, "com.follow.clash.BroadcastReceiver")
}