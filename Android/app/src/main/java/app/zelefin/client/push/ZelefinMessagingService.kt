package app.zelefin.client.push

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class ZelefinMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        ZelefinPush.didReceiveToken(applicationContext, token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        if (!ZelefinPush.isEnabled(applicationContext)) return
        ZelefinPush.show(
            applicationContext,
            message.data,
            message.notification?.title,
            message.notification?.body,
        )
    }
}
