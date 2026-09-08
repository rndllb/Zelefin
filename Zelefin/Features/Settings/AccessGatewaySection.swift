import SwiftUI

struct AccessGatewaySection: View {
    @State private var clientID = AccessGateway.clientID
    @State private var clientSecret = AccessGateway.clientSecret

    var body: some View {
        Section {
            TextField("Client ID or token ID", text: $clientID)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Client secret or access token", text: $clientSecret)
                .textContentType(.password)
        } header: {
            Text("Access Gateway")
        } footer: {
            Text("Needed when Jellyfin sits behind Cloudflare Zero Trust or Pangolin. Use a Cloudflare Access service token, or a Pangolin share-link token ID and token. Zelefin sends these on every request, including artwork and playback.")
        }
        .onChange(of: clientID) { _, value in
            AccessGateway.clientID = value
        }
        .onChange(of: clientSecret) { _, value in
            AccessGateway.clientSecret = value
        }
    }
}
