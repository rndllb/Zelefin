import Foundation

/// The request server Search, Discover, and the request sheet talk to.
enum RequestService: String, CaseIterable, Identifiable, Sendable {
    case seerr
    case ombi

    var id: String { rawValue }

    var name: String {
        switch self {
        case .seerr: "Seerr"
        case .ombi: "Ombi"
        }
    }
}

/// What Search, Discover, and the request sheet need from Seerr or Ombi. Ombi's titles and
/// requests are mapped onto the Seerr types, which the screens already draw.
protocol RequestServiceClient: Sendable {
    var service: RequestService { get }
    /// Seerr lets a request pick its Radarr or Sonarr server, quality, and folder. Ombi uses its defaults.
    var choosesDownloadServer: Bool { get }
    /// Seerr's genre, studio, and network rows.
    var browsesGenresAndCompanies: Bool { get }

    func search(term: String) async throws -> [SeerrTitle]
    /// The title as it stands now: whether it's on the server, and its open request, if any.
    func requestStatus(for title: SeerrTitle) async throws -> SeerrTitle
    func discoverHome() async -> SeerrDiscoverHome
    func discover(_ query: SeerrDiscoverQuery, page: Int) async throws -> SeerrDiscoverPage
    func currentUser() async throws -> SeerrUser
    func radarrServers() async throws -> [SeerrServiceServer]
    func sonarrServers() async throws -> [SeerrServiceServer]
    func radarrDetails(id: Int) async throws -> SeerrServiceDetails
    func sonarrDetails(id: Int) async throws -> SeerrServiceDetails
    func tvDetails(id: Int) async throws -> SeerrTvDetails
    func requestDetails(id: Int) async throws -> SeerrStoredRequest
    func request(_ draft: SeerrRequestDraft) async throws
    func approveRequest(id: Int, draft: SeerrRequestDraft) async throws
    func declineRequest(id: Int, kind: SeerrTitle.Kind) async throws
}

extension SeerrClient: RequestServiceClient {
    var service: RequestService { .seerr }
    var choosesDownloadServer: Bool { true }
    var browsesGenresAndCompanies: Bool { true }

    func declineRequest(id: Int, kind: SeerrTitle.Kind) async throws {
        try await declineRequest(id: id)
    }
}
