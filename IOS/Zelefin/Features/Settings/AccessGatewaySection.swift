import SwiftUI

struct AccessGatewaySection: View {
    @State private var clientID = AccessGateway.clientID
    @State private var clientSecret = AccessGateway.clientSecret

    var body: some View {
        Section {
            TextField(AppLanguage.string("connect.client_id", default: "Client ID or token ID"), text: $clientID)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField(AppLanguage.string("connect.client_secret", default: "Client secret or access token"), text: $clientSecret)
                .textContentType(.password)
        } header: {
            Text(AppLanguage.string("Access Gateway", default: "Access Gateway"))
        } footer: {
            Text(AppLanguage.string("Needed when this server sits behind Cloudflare Zero Trust or Pangolin. Use a Cloudflare Access service token, or a Pangolin share-link token ID and token. Zelefin sends these on every request, including artwork and playback.", default: "Needed when this server sits behind Cloudflare Zero Trust or Pangolin. Use a Cloudflare Access service token, or a Pangolin share-link token ID and token. Zelefin sends these on every request, including artwork and playback."))
        }
        .zelefinRowBackground()
        .onChange(of: clientID) { _, value in
            AccessGateway.clientID = value
        }
        .onChange(of: clientSecret) { _, value in
            AccessGateway.clientSecret = value
        }
    }
}
