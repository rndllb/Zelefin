package app.zelefin.client.push

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class ZelefinMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        ZelefinPush.didReceiveToken(applicationContext, token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val inbound = app.zelefin.client.session.SessionDisplayMessage.fromPush(
            message.data,
            message.notification?.title,
            message.notification?.body,
        )
        if (inbound != null) {
            app.zelefin.client.session.SessionMessageCenter.present(applicationContext, inbound, fromPush = true)
            return
        }
        if (!ZelefinPush.isEnabled(applicationContext)) return
        ZelefinPush.show(
            applicationContext,
            message.data,
            message.notification?.title,
            message.notification?.body,
        )
    }
}
