import XCTest
@testable import Zelefin

final class SiloDecodeTests: XCTestCase {
    func testHealthFixture() throws {
        let health = try SiloJSON.decoder.decode(SiloHealth.self, from: Data(#"""
        {"status":"ok","server_name":"Living Room","server_id":"abc","version":"0.9.0"}
        """#.utf8))
        XCTAssertTrue(health.isReady)
        XCTAssertEqual(health.displayName, "Living Room")
        XCTAssertEqual(health.version, "0.9.0")
    }

    func testLoginFixture() throws {
        let auth = try SiloJSON.decoder.decode(SiloAuthResponse.self, from: Data(#"""
        {
          "access_token":"tok_access",
          "refresh_token":"tok_refresh",
          "expires_in":3600,
          "user":{"id":7,"username":"ada","email":"ada@example.com","role":"admin"}
        }
        """#.utf8))
        XCTAssertEqual(auth.accessToken, "tok_access")
        XCTAssertEqual(auth.refreshToken, "tok_refresh")
        XCTAssertEqual(auth.user.id, 7)
        XCTAssertEqual(auth.user.username, "ada")
    }

    func testProfileFixture() throws {
        let envelope = try SiloJSON.decoder.decode(SiloProfilesResponse.self, from: Data(#"""
        {
          "profiles":[
            {"id":"p1","name":"Ada","has_pin":false,"is_child":false,"is_primary":true},
            {"id":"p2","name":"Kid","has_pin":true,"is_child":true,"is_primary":false}
          ]
        }
        """#.utf8))
        XCTAssertEqual(envelope.entries.count, 2)
        XCTAssertFalse(envelope.entries[0].hasPin)
        XCTAssertTrue(envelope.entries[1].hasPin)
        XCTAssertTrue(envelope.entries[1].isChild)
    }

    func testProfilesEnvelopeKeepsAvatarUploadFlag() throws {
        let envelope = try SiloJSON.decoder.decode(SiloProfilesResponse.self, from: Data(#"""
        {
          "items": [
            {
              "id": "p1",
              "name": "Ada",
              "avatar": "preset:dicebear:identicon:pepper-pebble",
              "avatar_source": "preset",
              "avatar_url": "/avatars/presets/fox.png",
              "has_pin": false,
              "is_child": false,
              "is_primary": true
            }
          ],
          "avatar_upload_enabled": true
        }
        """#.utf8))
        XCTAssertTrue(envelope.avatarUploadEnabled == true)
        XCTAssertEqual(envelope.entries.first?.avatar, "preset:dicebear:identicon:pepper-pebble")
        XCTAssertEqual(envelope.entries.first?.avatarSource, "preset")
        let resolved = envelope.resolved(against: URL(string: "https://silo.example")!)
        XCTAssertEqual(
            resolved.entries.first?.avatarURL?.absoluteString,
            "https://silo.example/avatars/presets/fox.png"
        )
    }

    func testAvatarPresetCatalogMatchesWebSeeds() {
        let first = SiloProfileAvatars.batch(styleID: "identicon", batch: 0).first
        XCTAssertEqual(first?.id, "dicebear:identicon:pepper-pebble")
        XCTAssertEqual(SiloProfileAvatars.presetRef(first!.id), "preset:dicebear:identicon:pepper-pebble")
        XCTAssertEqual(
            SiloProfileAvatars.presetID(from: "preset:dicebear:identicon:pepper-pebble"),
            "dicebear:identicon:pepper-pebble"
        )
        XCTAssertEqual(
            SiloProfileAvatars.displayURL(
                baseURL: URL(string: "https://silo.example")!,
                raw: "https://api.dicebear.com/9.x/identicon/svg?seed=pepper-pebble"
            )?.path,
            "/9.x/identicon/png"
        )
    }

    func testAvatarUpdateEncodesNullToClear() throws {
        let data = try SiloJSON.encoder.encode(SiloProfileAvatarUpdate(avatar: nil))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(object["avatar"] is NSNull)
    }

    func testCatalogItemMapsToMediaItem() throws {
        let item = try SiloJSON.decoder.decode(SiloCatalogItem.self, from: Data(#"""
        {
          "content_id":"movie-1",
          "play_content_id":"movie-1",
          "type":"movie",
          "title":"Dune",
          "year":2021,
          "runtime":155,
          "genres":["Sci-Fi"],
          "content_rating":"PG-13",
          "overview":"Arrakis.",
          "poster_url":"https://example.com/poster.jpg",
          "user_state":{"playback_position":120,"played":false,"is_favorite":true}
        }
        """#.utf8))
        let mapped = SiloMapper.mediaItem(from: item)
        XCTAssertEqual(mapped.id, "movie-1")
        XCTAssertEqual(mapped.name, "Dune")
        XCTAssertEqual(mapped.kind, .movie)
        XCTAssertEqual(mapped.year, 2021)
        XCTAssertEqual(mapped.runtime, 155 * 60)
        XCTAssertEqual(mapped.officialRating, "PG-13")
        XCTAssertEqual(mapped.playbackPosition, 120)
        XCTAssertTrue(mapped.isFavorite)
        XCTAssertEqual(mapped.posterURL?.absoluteString, "https://example.com/poster.jpg")
    }

    func testLegacyPlaybackDecisionMapsURL() throws {
        let decision = try SiloJSON.decoder.decode(SiloPlaybackDecision.self, from: Data(#"""
        {
          "session_id":"sess-1",
          "stream_url":"https://silo.example/stream/1"
        }
        """#.utf8))
        XCTAssertEqual(decision.sessionID, "sess-1")
        XCTAssertEqual(decision.streamURL?.absoluteString, "https://silo.example/stream/1")
    }

    func testPlaybackV3DecisionMapsStreamURL() throws {
        let decision = try SiloJSON.decoder.decode(SiloPlaybackDecision.self, from: Data(#"""
        {
          "protocol_version":3,
          "outcome":"playable",
          "session_id":"11111111-1111-4111-8111-111111111111",
          "playback_plan":{
            "delivery":"server_remux_hls",
            "session_id":"11111111-1111-4111-8111-111111111111",
            "stream":{"url":"/stream/11111111-1111-4111-8111-111111111111","protocol":"hls","container":"hls"}
          }
        }
        """#.utf8))
        XCTAssertEqual(decision.outcome, "playable")
        XCTAssertEqual(decision.playbackPlan?.stream?.url, "/stream/11111111-1111-4111-8111-111111111111")
        XCTAssertEqual(decision.playbackPlan?.stream?.protocolKind, "hls")
    }

    func testSavedSessionWithoutBackendDefaultsToJellyfin() throws {
        let data = Data(#"""
        {
          "serverURL":"http://jellyfin.local:8096",
          "accessToken":"token",
          "userID":"u1",
          "userName":"Ada",
          "deviceID":"d1"
        }
        """#.utf8)
        let session = try JSONDecoder().decode(SavedSession.self, from: data)
        XCTAssertEqual(session.backend, .jellyfin)
        XCTAssertFalse(session.usesSilo)
        XCTAssertNil(session.refreshToken)
        XCTAssertNil(session.profileID)
    }

    func testSavedSessionRoundTripKeepsSiloFields() throws {
        let original = SavedSession(
            serverURL: URL(string: "http://silo.local:8080")!,
            accessToken: "a",
            userID: "7",
            userName: "Ada",
            deviceID: "d1",
            serverName: "Living Room",
            backend: .silo,
            refreshToken: "r",
            profileID: "p1",
            profileToken: "pt",
            profileName: "Ada",
            userRole: "admin",
            isPrimaryProfile: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SavedSession.self, from: data)
        XCTAssertEqual(decoded.backend, .silo)
        XCTAssertEqual(decoded.refreshToken, "r")
        XCTAssertEqual(decoded.profileID, "p1")
        XCTAssertEqual(decoded.profileToken, "pt")
        XCTAssertTrue(decoded.usesSilo)
        XCTAssertEqual(decoded.userRole, "admin")
        XCTAssertTrue(decoded.isPrimaryProfile)
    }

    func testPendingSignInNeedsPINWhenAnyProfileIsLocked() {
        let pending = SiloPendingSignIn(
            serverURL: URL(string: "http://silo.local")!,
            accessToken: "a",
            refreshToken: "r",
            userID: "1",
            userName: "Ada",
            deviceID: "d",
            serverName: "Silo",
            serverVersion: nil,
            userRole: "admin",
            profiles: [
                SiloHouseholdProfile(id: "p1", name: "Ada", avatarURL: nil, hasPin: true, isChild: false, isPrimary: true)
            ]
        )
        XCTAssertTrue(pending.needsProfileChoice)
        XCTAssertNil(pending.singleUnlockedProfile)
    }

    func testSingleUnlockedProfileStillLeavesChoiceToTheClient() {
        let pending = SiloPendingSignIn(
            serverURL: URL(string: "http://silo.local")!,
            accessToken: "a",
            refreshToken: "r",
            userID: "1",
            userName: "Ada",
            deviceID: "d",
            serverName: "Silo",
            serverVersion: nil,
            userRole: "user",
            profiles: [
                SiloHouseholdProfile(id: "p1", name: "Ada", avatarURL: nil, hasPin: false, isChild: false, isPrimary: true)
            ]
        )
        XCTAssertNotNil(pending.singleUnlockedProfile)
        XCTAssertFalse(pending.needsProfileChoice)
    }

    func testHomeSectionsMapContinueWatching() throws {
        let feed = try SiloJSON.decoder.decode(SiloHomeSectionsResponse.self, from: Data(#"""
        {
          "sections": [
            {
              "id": "continue",
              "section_type": "continue_watching",
              "title": "Continue Watching",
              "items": [
                {"content_id": "ep-1", "type": "episode", "title": "Pilot", "position_seconds": 42}
              ]
            },
            {
              "id": "recent-movies",
              "section_type": "recently_added_movies",
              "title": "Recently Added Movies",
              "items": [
                {"content_id": "movie-2", "type": "movie", "title": "Dune"}
              ]
            }
          ]
        }
        """#.utf8))
        let mapped = SiloMapper.homeFeed(from: feed)
        XCTAssertEqual(mapped.resume.map(\.id), ["ep-1"])
        XCTAssertEqual(mapped.resume.first?.playbackPosition, 42)
        XCTAssertEqual(mapped.librarySections.map(\.title), ["Recently Added Movies"])
        XCTAssertEqual(mapped.librarySections.first?.items.map(\.id), ["movie-2"])
    }

    func testHomeSectionsSplitNextUpAndFeaturedHero() throws {
        let feed = try SiloJSON.decoder.decode(SiloHomeSectionsResponse.self, from: Data(#"""
        {
          "sections": [
            {
              "id": "continue",
              "section_type": "continue_watching",
              "title": "Continue Watching",
              "items": [
                {"content_id": "ep-1", "type": "episode", "title": "Pilot", "item_source": "in_progress"},
                {"content_id": "ep-2", "type": "episode", "title": "On Deck", "item_source": "next_up"}
              ]
            },
            {
              "id": "hero",
              "section_type": "recently_added",
              "title": "Spotlight",
              "featured": true,
              "items": [
                {"content_id": "movie-1", "type": "movie", "title": "Heat", "backdrop_url": "https://example.com/hero.jpg", "logo_url": "https://example.com/logo.png"}
              ]
            }
          ]
        }
        """#.utf8))
        let mapped = SiloMapper.homeFeed(from: feed)
        XCTAssertEqual(mapped.resume.map(\.id), ["ep-1"])
        XCTAssertEqual(mapped.nextUp.map(\.id), ["ep-2"])
        XCTAssertEqual(mapped.nextUp.first?.queueKind, .nextUp)
        XCTAssertEqual(mapped.featured.map(\.id), ["movie-1"])
        XCTAssertEqual(mapped.featured.first?.backdropURL?.absoluteString, "https://example.com/hero.jpg")
        XCTAssertEqual(mapped.featured.first?.logoURL?.absoluteString, "https://example.com/logo.png")
        XCTAssertTrue(mapped.featured.first?.hasHeroBackdrop == true)
    }

    func testHomeSectionsItemsEnvelopeMapsRecentlyAddedRows() throws {
        let feed = try SiloJSON.decoder.decode(SiloHomeSectionsResponse.self, from: Data(#"""
        {
          "items": [
            {
              "id": "recently_added_movies",
              "section_type": "recently_added",
              "title": "Recently Added Movies",
              "items": [
                {"content_id": "movie:heat", "type": "movie", "title": "Heat", "backdrop_url": "https://example.com/heat.jpg"},
                {"type": "movie", "title": "Missing ID"}
              ]
            },
            {
              "id": "recently_added_shows",
              "section_type": "recently_added",
              "title": "Recently Added Shows",
              "items": [
                {"content_id": "series:ted", "type": "series", "title": "Ted Lasso"}
              ]
            }
          ]
        }
        """#.utf8))
        XCTAssertEqual(feed.rows.map(\.resolvedID), ["recently_added_movies", "recently_added_shows"])
        let mapped = SiloMapper.homeFeed(from: feed)
        let remapped = SiloMapper.canonicalLibraryHome(mapped.librarySections, libraries: [])
        XCTAssertEqual(remapped.movies?.id, "library-movies")
        XCTAssertEqual(remapped.movies?.items.map(\.id), ["movie:heat"])
        XCTAssertEqual(remapped.shows?.id, "library-shows")
        XCTAssertEqual(remapped.shows?.items.map(\.id), ["series:ted"])
        XCTAssertEqual(SiloMapper.sortQuery(.dateAdded).sort, "added_at")
        XCTAssertEqual(SiloMapper.catalogType(for: .shows), "series")
    }

    func testPasswordCapabilityAndAdminUserDecode() throws {
        let capability = try SiloJSON.decoder.decode(SiloPasswordCapability.self, from: Data(#"""
        {
          "allowed": true,
          "requires_current_password": true,
          "minimum_password_length": 8
        }
        """#.utf8))
        XCTAssertTrue(capability.canChange)
        XCTAssertEqual(capability.minimumLength, 8)

        let users = try SiloJSON.decoder.decode(SiloAdminUsersResponse.self, from: Data(#"""
        {
          "items": [
            {"id": "7", "username": "ada", "email": "ada@example.test", "role": "admin", "enabled": true}
          ]
        }
        """#.utf8))
        XCTAssertEqual(users.entries.first?.username, "ada")
        XCTAssertTrue(users.entries.first?.isAdmin == true)

        let profiles = try SiloJSON.decoder.decode(SiloProfilesResponse.self, from: Data(#"""
        {
          "items": [
            {"id": "p1", "name": "Ada", "has_pin": false, "is_child": false, "is_primary": true}
          ]
        }
        """#.utf8))
        XCTAssertEqual(profiles.entries.map(\.id), ["p1"])
        XCTAssertTrue(profiles.entries.first?.isPrimary == true)
    }

    func testSiloAdminSurfacesDecode() throws {
        let invitation = try SiloJSON.decoder.decode(SiloPageCollection<SiloAdminInvitation>.self, from: Data(#"""
        {
          "items": [
            {"id":"9","email":"ada@example.test","role":"user","status":"pending","invited_by_name":"Ada"}
          ]
        }
        """#.utf8))
        XCTAssertEqual(invitation.entries.first?.email, "ada@example.test")
        XCTAssertTrue(invitation.entries.first?.isPending == true)

        let sessions = try SiloJSON.decoder.decode(SiloPageCollection<SiloAdminSession>.self, from: Data(#"""
        {
          "items": [
            {"session_id":"s1","username":"ada","media_title":"Heat","play_method":"direct","is_paused":false,"position_seconds":42}
          ]
        }
        """#.utf8))
        XCTAssertEqual(sessions.entries.first?.title, "Heat")
        XCTAssertEqual(sessions.entries.first?.username, "ada")

        let nodes = try SiloJSON.decoder.decode(SiloPageCollection<SiloAdminNode>.self, from: Data(#"""
        {
          "items": [
            {"id":"1","name":"Transcode","type":"transcode","healthy":true,"enabled":true,"active_jobs":2}
          ]
        }
        """#.utf8))
        XCTAssertEqual(nodes.entries.first?.name, "Transcode")
        XCTAssertTrue(nodes.entries.first?.healthy == true)

        let libraries = try SiloJSON.decoder.decode(SiloPageCollection<SiloAdminLibrary>.self, from: Data(#"""
        {
          "items": [
            {"id":"3","name":"Movies","type":"movies","enabled":true}
          ]
        }
        """#.utf8))
        XCTAssertEqual(libraries.entries.first?.id, "3")
        XCTAssertEqual(libraries.entries.first?.name, "Movies")
    }

    func testRecommendationRowsAndGenreMapping() throws {
        let rows = try SiloJSON.decoder.decode(SiloRecommendationRowsResponse.self, from: Data(#"""
        {
          "items": [
            {
              "type": "cluster",
              "title": "Because you like Crime",
              "kind": "genre",
              "key": "Crime",
              "items": [{"content_id": "movie-3", "type": "movie", "title": "Heat"}]
            }
          ]
        }
        """#.utf8))
        let sections = SiloMapper.recommendationSections(from: rows.entries)
        XCTAssertEqual(sections.map(\.id), ["recommend-genre-Crime"])
        XCTAssertEqual(sections.first?.title, "Because you like Crime")
        XCTAssertEqual(sections.first?.items.map(\.id), ["movie-3"])

        let genre = SiloMapper.genreItem(name: "Action")
        XCTAssertEqual(genre.id, "Action")
        XCTAssertEqual(genre.kind, .genre)
        XCTAssertEqual(genre.name, "Action")
    }

    func testCalendarEventMapsUpcomingEpisode() throws {
        let calendar = try SiloJSON.decoder.decode(SiloCalendar.self, from: Data(#"""
        {
          "events": [
            {
              "date": "2026-09-20",
              "items": [
                {
                  "content_id": "episode:severance-s02e03",
                  "type": "episode",
                  "title": "Severance",
                  "episode_title": "Who Is Alive?",
                  "series_id": "series:severance",
                  "season_number": 2,
                  "episode_number": 3,
                  "air_date": "2026-09-20",
                  "watched": false
                },
                {
                  "content_id": "episode:done",
                  "type": "episode",
                  "title": "Watched Show",
                  "watched": true
                }
              ]
            }
          ]
        }
        """#.utf8))
        let items = calendar.allEvents.compactMap(SiloMapper.mediaItem(from:))
        XCTAssertEqual(items.map(\.id), ["episode:severance-s02e03"])
        XCTAssertEqual(items.first?.seriesName, "Severance")
        XCTAssertEqual(items.first?.seasonIndex, 2)
        XCTAssertEqual(items.first?.episodeIndex, 3)
        XCTAssertEqual(items.first?.queueKind, .nextUp)
    }

    func testPlaybackV3RequestUsesNeutralContractKeys() throws {
        let request = SiloPlaybackStart.v3Request(fileID: 42, profileID: "p1", startPosition: 12.5)
        let object = try JSONSerialization.jsonObject(with: try SiloJSON.encoder.encode(request)) as? [String: Any]
        XCTAssertEqual(object?["protocol_version"] as? Int, 3)
        XCTAssertEqual(object?["file_id"] as? Int, 42)
        XCTAssertEqual(object?["profile_id"] as? String, "p1")
        XCTAssertEqual(object?["quality_preference"] as? String, "original")
        XCTAssertEqual(object?["subtitle_fidelity_preference"] as? String, "preserve")
        XCTAssertEqual(object?["metered"] as? Bool, false)
        XCTAssertNil(object?["bandwidth_cap_kbps"])
        XCTAssertNil(object?["bandwidth_estimate_kbps"])
        let features = object?["client_features"] as? [String]
        XCTAssertTrue(features?.contains("header_authenticated_media_v1") == true)
        XCTAssertTrue(features?.contains("playback_plan_v3") == true)
        XCTAssertTrue(features?.contains("embedded_subtitles_v1") == true)
        XCTAssertTrue(features?.contains("software_video_decode_v1") == true)
        let capabilities = object?["client_capabilities"] as? [String: Any]
        XCTAssertEqual(capabilities?["video_evidence"] as? String, "platform_attested")
        XCTAssertEqual(capabilities?["audio_evidence"] as? String, "declared")
        XCTAssertFalse((capabilities?["video_decode"] as? [Any] ?? []).isEmpty)
        let decode = (capabilities?["video_decode"] as? [[String: Any]]) ?? []
        XCTAssertTrue(decode.contains { $0["codec"] as? String == "h264" && $0["hardware"] as? Bool == true })
        let context = object?["client_playback_context"] as? [String: Any]
        XCTAssertNotNil(context?["deliveries"])
        XCTAssertEqual(context?["form_factor"] as? String, "mobile")
        let device = context?["device"] as? [String: Any]
        XCTAssertEqual(device?["platform"] as? String, "ios")
        XCTAssertNotNil(device?["platform_details"])
        let output = context?["output"] as? [String: Any]
        XCTAssertNotNil(output?["output_context_id"])
        let deliveries = context?["deliveries"] as? [String: Any]
        let originalHTTP = deliveries?["original_http"] as? [String: Any]
        XCTAssertEqual(originalHTTP?["enabled"] as? Bool, true)
        XCTAssertEqual(originalHTTP?["supported_on_device"] as? Bool, true)
        let originalClaims = originalHTTP?["validated_claims"] as? [String]
        XCTAssertTrue(originalClaims?.contains("client_managed_dynamic_range_v1") == true)
        XCTAssertTrue(originalClaims?.contains("client_selected_audio_track_v1") == true)
        XCTAssertTrue(originalClaims?.contains("client_dv8_base_layer_fallback_v1") == true)
        let defaultHLS = deliveries?["hls"] as? [String: Any]
        XCTAssertEqual(defaultHLS?["containers"] as? [String], ["hls", "fmp4", "mp4"])
        XCTAssertEqual(
            SiloPlaybackStart.playbackMethod(protocolKind: "http_progressive", delivery: "original_http"),
            .directPlay
        )
        XCTAssertEqual(
            SiloPlaybackStart.playbackMethod(protocolKind: "hls", delivery: "hls_copy"),
            .remux
        )
        XCTAssertEqual(SiloPlaybackStart.qualityPreference(allowDirectPlay: true, capKbps: nil), "original")
        XCTAssertEqual(SiloPlaybackStart.qualityPreference(allowDirectPlay: true, capKbps: 8_000), "auto")
        XCTAssertEqual(SiloPlaybackStart.qualityPreference(allowDirectPlay: false, capKbps: nil), "auto")
        XCTAssertEqual(SiloPlaybackStart.hlsContainers(preferFMP4: true), ["hls", "fmp4", "mp4"])
        XCTAssertEqual(SiloPlaybackStart.hlsContainers(preferFMP4: false), ["hls", "mpegts"])
        XCTAssertNil(SiloPlaybackStart.startBitrate(selected: .auto))
        XCTAssertEqual(SiloPlaybackStart.startBitrate(selected: .mbps8), PlaybackQuality.mbps8.bitsPerSecond)
        XCTAssertTrue(
            SiloPlaybackStart.clientOwnsPlayhead(
                protocolKind: "http_progressive",
                delivery: "original_http",
                timeline: SiloPlaybackTimeline(playerStartSeconds: 120, canSeekAnywhere: true)
            )
        )
        XCTAssertFalse(
            SiloPlaybackStart.clientOwnsPlayhead(
                protocolKind: "hls",
                delivery: "hls_copy",
                timeline: SiloPlaybackTimeline(playerStartSeconds: 0, canSeekAnywhere: false)
            )
        )
        XCTAssertEqual(
            SiloPlaybackStart.resolvedPlayerStart(
                requested: 120,
                timeline: SiloPlaybackTimeline(playerStartSeconds: 0, canSeekAnywhere: true)
            ),
            120
        )
        XCTAssertEqual(
            SiloPlaybackStart.resolvedPlayerStart(
                requested: 120,
                timeline: SiloPlaybackTimeline(playerStartSeconds: 120, canSeekAnywhere: true)
            ),
            120
        )
        XCTAssertEqual(
            SiloPlaybackStart.resolvedPlayerStart(
                requested: 120,
                timeline: SiloPlaybackTimeline(playerStartSeconds: 0, streamOriginSeconds: 120, canSeekAnywhere: false)
            ),
            120
        )
    }

    func testPlaybackV3RequestSendsBandwidthCapFromMaxBitrate() throws {
        XCTAssertNil(SiloPlaybackStart.bandwidthCapKbps(from: nil))
        XCTAssertNil(SiloPlaybackStart.bandwidthCapKbps(from: AVDeviceProfileFactory.maxBitrate))
        XCTAssertEqual(SiloPlaybackStart.bandwidthCapKbps(from: 4_000_000), 4_000)
        XCTAssertEqual(SiloPlaybackStart.bandwidthCapKbps(from: 50_000), 100)

        let request = SiloPlaybackStart.v3Request(
            fileID: 42,
            profileID: "p1",
            startPosition: 0,
            maxBitrate: 8_000_000
        )
        let object = try JSONSerialization.jsonObject(with: try SiloJSON.encoder.encode(request)) as? [String: Any]
        XCTAssertEqual(object?["quality_preference"] as? String, "auto")
        XCTAssertEqual(object?["bandwidth_cap_kbps"] as? Int, 8_000)
        XCTAssertEqual(object?["bandwidth_estimate_kbps"] as? Int, 8_000)
        XCTAssertEqual(object?["audio_track_index"] as? Int, nil)

        let withSubtitle = SiloPlaybackStart.v3Request(
            fileID: 42,
            profileID: "p1",
            startPosition: 0,
            subtitleIndex: 2
        )
        let subtitleBody = try JSONSerialization.jsonObject(with: try SiloJSON.encoder.encode(withSubtitle)) as? [String: Any]
        XCTAssertEqual(subtitleBody?["subtitle_track_index"] as? Int, 2)

        let remux = SiloPlaybackStart.v3Request(
            fileID: 42,
            profileID: "p1",
            startPosition: 0,
            allowDirectPlay: false,
            preferFMP4InHLS: false
        )
        let remuxBody = try JSONSerialization.jsonObject(with: try SiloJSON.encoder.encode(remux)) as? [String: Any]
        XCTAssertEqual(remuxBody?["quality_preference"] as? String, "auto")
        let remuxDeliveries = (remuxBody?["client_playback_context"] as? [String: Any])?["deliveries"] as? [String: Any]
        let original = remuxDeliveries?["original_http"] as? [String: Any]
        XCTAssertEqual(original?["enabled"] as? Bool, false)
        let hls = remuxDeliveries?["hls"] as? [String: Any]
        XCTAssertEqual(hls?["containers"] as? [String], ["hls", "mpegts"])
    }

    func testOpenSubtitlesIsBuiltIntoSilo() throws {
        XCTAssertTrue(SiloOpenSubtitles.isAvailable(status: nil))
        let available = try SiloJSON.decoder.decode(SiloSubtitleProviderStatus.self, from: Data(#"""
        {"allowed":true,"enabled":true,"providers":["opensubtitles"],"revision":"1","schema_version":1,"state":"available"}
        """#.utf8))
        XCTAssertTrue(SiloOpenSubtitles.isAvailable(status: available))
        XCTAssertEqual(available.names, ["opensubtitles"])
        let unconfigured = try SiloJSON.decoder.decode(SiloSubtitleProviderStatus.self, from: Data(#"""
        {"allowed":false,"enabled":false,"providers":[],"revision":"1","schema_version":1,"state":"not_configured"}
        """#.utf8))
        XCTAssertTrue(SiloOpenSubtitles.isAvailable(status: unconfigured))
        let disabled = try SiloJSON.decoder.decode(SiloSubtitleProviderStatus.self, from: Data(#"""
        {"allowed":false,"enabled":false,"providers":[],"revision":"1","schema_version":1,"state":"disabled"}
        """#.utf8))
        XCTAssertTrue(SiloOpenSubtitles.isAvailable(status: disabled))
        let blocked = try SiloJSON.decoder.decode(SiloSubtitleProviderStatus.self, from: Data(#"""
        {"allowed":false,"enabled":true,"providers":["opensubtitles"],"revision":"1","schema_version":1,"state":"available"}
        """#.utf8))
        XCTAssertFalse(SiloOpenSubtitles.isAvailable(status: blocked))
    }

    func testSiloSubtitleProvidersIncludeSubDLAndSubsource() throws {
        XCTAssertEqual(SiloSubtitleProviders.displayName("opensubtitles"), "OpenSubtitles")
        XCTAssertEqual(SiloSubtitleProviders.displayName("subdl"), "SubDL")
        XCTAssertEqual(SiloSubtitleProviders.displayName("subsource"), "Subsource")
        XCTAssertEqual(
            SiloSubtitleProviders.normalized(["SubSource", "opensubtitles", "subdl"]),
            ["opensubtitles", "subdl", "subsource"]
        )
        let connected = try SiloJSON.decoder.decode(SiloSubtitleProviderStatus.self, from: Data(#"""
        {"enabled":true,"providers":["opensubtitles","subdl","subsource"]}
        """#.utf8))
        XCTAssertEqual(SiloSubtitleProviders.listed(from: connected), ["opensubtitles", "subdl", "subsource"])
        let unavailable = SiloHTTPError(
            statusCode: 503,
            code: "dependency_unavailable",
            message: "Subtitle access is not configured."
        )
        XCTAssertTrue(unavailable.shouldUseLegacySubtitles)
        XCTAssertTrue(SiloHTTPError(statusCode: 504, code: nil, message: "Gateway Timeout").shouldUseLegacySubtitles)
        XCTAssertEqual(
            SiloJSON.error(
                statusCode: 503,
                data: Data(#"""
                {"type":"https://silo.example/problems/dependency_unavailable","title":"Dependency unavailable","detail":"Subtitle access is not configured.","status":503}
                """#.utf8)
            ).code,
            "dependency_unavailable"
        )
    }

    func testOpenSubtitlesSearchBodyEncodesStringFileID() throws {
        let body = SiloSubtitleSearchBody(mediaFileID: "42", languages: ["en"])
        let object = try JSONSerialization.jsonObject(with: try SiloJSON.encoder.encode(body)) as? [String: Any]
        XCTAssertEqual(object?["media_file_id"] as? String, "42")
        XCTAssertNil(object?["media_file_id"] as? Int)
        XCTAssertEqual(object?["languages"] as? [String], ["en"])
    }

    func testOpenSubtitlesSearchBodyV1EncodesIntFileID() throws {
        let body = SiloSubtitleSearchBodyV1(mediaFileID: 42, languages: ["en"])
        let object = try JSONSerialization.jsonObject(with: try SiloJSON.encoder.encode(body)) as? [String: Any]
        XCTAssertEqual(object?["media_file_id"] as? Int, 42)
        XCTAssertEqual(object?["languages"] as? [String], ["en"])
    }

    func testOpenSubtitlesDownloadBodyV1EncodesIntFileID() throws {
        let body = SiloSubtitleDownloadBodyV1(
            mediaFileID: 42,
            provider: "opensubtitles",
            subtitleID: "abc",
            language: "en",
            releaseName: "Movie.2024",
            format: "srt",
            score: 0.9,
            hearingImpaired: false
        )
        let object = try JSONSerialization.jsonObject(with: try SiloJSON.encoder.encode(body)) as? [String: Any]
        XCTAssertEqual(object?["media_file_id"] as? Int, 42)
        XCTAssertEqual(object?["subtitle_id"] as? String, "abc")
        XCTAssertEqual(object?["format"] as? String, "srt")
    }

    func testFileIDScrapeIgnoresGenreIDs() {
        let ids = SiloFileID.scrape(from: Data(#"""
        {"content_id":"movie:one","genre_ids":[28,12],"year":2024,"tmdb_id":12345}
        """#.utf8))
        XCTAssertEqual(ids, [])
        let withFile = SiloFileID.scrape(from: Data(#"""
        {"content_id":"movie:one","genre_ids":[28,12],"files":[{"file_id":"71"}]}
        """#.utf8))
        XCTAssertEqual(withFile, [71])
    }

    func testPlaybackPlanSubtitleInventoryMapsSidecars() async throws {
        let data = Data(#"""
        {
          "protocol_version": 3,
          "outcome": "playable",
          "session_id": "11111111-1111-4111-8111-111111111111",
          "playback_plan": {
            "delivery": "original_http",
            "session_id": "11111111-1111-4111-8111-111111111111",
            "stream": { "url": "/stream/11111111-1111-4111-8111-111111111111", "protocol": "http_progressive" },
            "subtitle": {
              "inventory": [
                {
                  "track_id": "file:42:subtitle:0",
                  "combined_index": 0,
                  "source": "external",
                  "codec": "srt",
                  "language": "eng",
                  "label": "English",
                  "forced": false,
                  "default": false,
                  "hearing_impaired": false,
                  "delivery": "sidecar",
                  "url": "/stream/11111111-1111-4111-8111-111111111111/subtitles/0.vtt?file_id=42"
                },
                {
                  "track_id": "file:42:subtitle:1",
                  "combined_index": 1,
                  "source": "embedded",
                  "codec": "subrip",
                  "language": "fre",
                  "label": "French",
                  "forced": false,
                  "default": false,
                  "hearing_impaired": false,
                  "delivery": "embedded"
                },
                {
                  "track_id": "file:42:subtitle:3",
                  "combined_index": 3,
                  "source": "embedded",
                  "codec": "dvd_subtitle",
                  "language": "deu",
                  "label": "German",
                  "forced": false,
                  "default": false,
                  "hearing_impaired": false,
                  "delivery": "burn_in_only"
                },
                {
                  "track_id": "file:42:subtitle:2",
                  "combined_index": 2,
                  "source": "downloaded",
                  "codec": "srt",
                  "language": "spa",
                  "label": "Spanish (downloaded)",
                  "forced": false,
                  "default": false,
                  "hearing_impaired": false,
                  "delivery": "sidecar",
                  "url": "/stream/11111111-1111-4111-8111-111111111111/subtitles/2.vtt?file_id=42"
                }
              ]
            }
          }
        }
        """#.utf8)
        let decision = try SiloJSON.decoder.decode(SiloPlaybackDecision.self, from: data)
        let inventory = try XCTUnwrap(decision.playbackPlan?.subtitle?.inventory)
        XCTAssertEqual(inventory.count, 4)
        let base = URL(string: "https://silo.example")!
        let overlay = await SiloPlaybackStart.subtitleOverlay(
            inventory: inventory,
            subtitlesOff: false,
            resolve: { SiloAPIClient.mediaURL(baseURL: base, raw: $0) }
        )
        XCTAssertEqual(overlay.tracks.map(\.title), ["English", "French", "Spanish (downloaded)"])
        XCTAssertEqual(overlay.tracks.map(\.id), [0, 1, 2])
        XCTAssertEqual(overlay.sidecars.count, 2)
        XCTAssertEqual(overlay.sidecars[0].formatHint, "vtt")
        XCTAssertTrue(overlay.tracks[2].isSelected)
        XCTAssertTrue(
            overlay.sidecars[1].url.absoluteString.contains("/api/v1/stream/11111111-1111-4111-8111-111111111111/subtitles/2.vtt")
        )
        XCTAssertEqual(SiloPlaybackStart.subtitleStartIndex(3), 3)
        XCTAssertEqual(SiloPlaybackStart.subtitleStartIndex(-1), -1)
        XCTAssertNil(SiloPlaybackStart.subtitleStartIndex(nil))
        XCTAssertEqual(SiloPlaybackStart.subtitleFormatHint(codec: "subrip", url: "/stream/x/subtitles/4.vtt?file_id=1"), "vtt")
        let marked = SiloPlaybackStart.applyingSubtitleSelection(overlay.tracks, requested: 1)
        XCTAssertTrue(marked[1].isSelected)
        XCTAssertFalse(marked[2].isSelected)
    }

    func testOpenSubtitlesSearchResultsDecodeStringIDs() throws {
        let payload = try SiloJSON.decoder.decode(SiloSubtitleSearchResults.self, from: Data(#"""
        {
          "results": [
            {
              "id": "abc",
              "provider": "opensubtitles",
              "language": "en",
              "release_name": "Movie.2024.1080p",
              "format": "srt",
              "score": 0.9,
              "downloads": 12,
              "hearing_impaired": false
            }
          ],
          "warnings": []
        }
        """#.utf8))
        let matches = payload.matches(mediaFileID: "42")
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].id, "42:opensubtitles:abc")
        XCTAssertEqual(matches[0].silo?.mediaFileID, "42")
        XCTAssertEqual(matches[0].silo?.subtitleID, "abc")
        let empty = try SiloJSON.decoder.decode(SiloSubtitleSearchResults.self, from: Data(#"""
        {"results":null,"warnings":null}
        """#.utf8))
        XCTAssertTrue(empty.matches(mediaFileID: "42").isEmpty)
    }

    func testMediaVersionDecodesStringFileID() throws {
        let version = try SiloJSON.decoder.decode(SiloMediaVersion.self, from: Data(#"""
        {"file_id":"42","name":"1080p"}
        """#.utf8))
        XCTAssertEqual(version.resolvedFileID, 42)
        XCTAssertEqual(version.name, "1080p")
    }

    func testPlaybackV3DecisionScrapesOriginalHTTPURL() throws {
        let data = Data(#"""
        {
          "protocol_version": 3,
          "outcome": "playable",
          "session_id": "11111111-1111-4111-8111-111111111111",
          "playback_plan": {
            "delivery": "original_http",
            "session_id": "11111111-1111-4111-8111-111111111111",
            "stream": {
              "url": "/stream/11111111-1111-4111-8111-111111111111",
              "protocol": "http_progressive",
              "container": "mp4",
              "headers": {},
              "header_refresh": "none"
            },
            "timeline": {
              "player_start_seconds": 0,
              "stream_origin_seconds": 0,
              "can_seek_anywhere": true
            }
          }
        }
        """#.utf8)
        let decision = try SiloJSON.decoder.decode(SiloPlaybackDecision.self, from: data)
        XCTAssertEqual(decision.resolvedStreamPath, "/stream/11111111-1111-4111-8111-111111111111")
        XCTAssertEqual(SiloPlaybackStart.scrapeStreamURL(from: data), "/stream/11111111-1111-4111-8111-111111111111")
        XCTAssertEqual(decision.playbackPlan?.timeline?.canSeekAnywhere, true)
        XCTAssertEqual(decision.playbackPlan?.timeline?.playerStartSeconds, 0)
        XCTAssertEqual(
            SiloPlaybackStart.resolvedPlayerStart(requested: 120, timeline: decision.playbackPlan?.timeline),
            120
        )
        XCTAssertTrue(
            SiloPlaybackStart.clientOwnsPlayhead(
                protocolKind: decision.playbackPlan?.stream?.protocolKind ?? "",
                delivery: decision.playbackPlan?.delivery ?? "",
                timeline: decision.playbackPlan?.timeline
            )
        )
        XCTAssertEqual(
            PlaybackResumePolicy.clientStartPosition(
                method: SiloPlaybackStart.playbackMethod(
                    protocolKind: decision.playbackPlan?.stream?.protocolKind ?? "",
                    delivery: decision.playbackPlan?.delivery ?? ""
                ),
                startTime: SiloPlaybackStart.resolvedPlayerStart(
                    requested: 120,
                    timeline: decision.playbackPlan?.timeline
                ),
                clientOwnsPlayhead: true
            ),
            120
        )
    }

    func testPlaybackV3TerminalMessageWinsOverUpgradeError() {
        var decision = SiloPlaybackDecision()
        decision.terminal = SiloPlaybackTerminal(reason: "adaptation_unavailable", message: "No compatible route.", retryable: false)
        let message = SiloPlaybackStart.unsupportedMessage(
            for: decision,
            error: SiloHTTPError(statusCode: 426, code: "client_upgrade_required", message: "Upgrade")
        )
        XCTAssertEqual(message, "No compatible route.")
    }

    func testMedia3OnlyErrorCopy() {
        var decision = SiloPlaybackDecision()
        decision.playbackPlan = SiloPlaybackPlanEnvelope(delivery: "media3_only")
        let message = SiloPlaybackStart.unsupportedMessage(for: decision, error: nil)
        XCTAssertTrue(message.localizedCaseInsensitiveContains("Media3"))
    }

    func testPathEncodingKeepsIDsSafe() {
        XCTAssertEqual(SiloAPIClient.path("movie-1"), "movie-1")
        XCTAssertEqual(SiloAPIClient.path("movie:one"), "movie:one")
        XCTAssertEqual(SiloAPIClient.path("a/b"), "a%2Fb")
    }

    func testMediaURLPrefixesAPIStreamPath() {
        let base = URL(string: "http://10.0.0.1:8090/")!
        XCTAssertEqual(
            SiloAPIClient.mediaURL(baseURL: base, raw: "/stream/11111111-1111-4111-8111-111111111111")?.absoluteString,
            "http://10.0.0.1:8090/api/v1/stream/11111111-1111-4111-8111-111111111111"
        )
        XCTAssertEqual(
            SiloAPIClient.mediaURL(baseURL: base, raw: "/stream/11111111-1111-4111-8111-111111111111?seek=12.5")?.absoluteString,
            "http://10.0.0.1:8090/api/v1/stream/11111111-1111-4111-8111-111111111111?seek=12.5"
        )
        XCTAssertEqual(
            SiloAPIClient.mediaURL(baseURL: base, raw: "/api/v1/stream/already")?.absoluteString,
            "http://10.0.0.1:8090/api/v1/stream/already"
        )
        XCTAssertEqual(
            SiloAPIClient.mediaURL(baseURL: base, raw: "/stream/v3/11111111-1111-4111-8111-111111111111")?.absoluteString,
            "http://10.0.0.1:8090/api/v1/stream/11111111-1111-4111-8111-111111111111"
        )
        XCTAssertEqual(
            SiloAPIClient.mediaURL(baseURL: base, raw: "https://proxy.example/stream/v3/session-1")?.absoluteString,
            "https://proxy.example/stream/v3/session-1"
        )
        let publicBase = URL(string: "https://silo.example")!
        XCTAssertEqual(
            SiloAPIClient.mediaURL(
                baseURL: publicBase,
                raw: "http://192.168.4.20:8090/stream/v3/11111111-1111-4111-8111-111111111111"
            )?.absoluteString,
            "https://silo.example/api/v1/stream/11111111-1111-4111-8111-111111111111"
        )
        XCTAssertEqual(
            SiloAPIClient.mediaURL(
                baseURL: publicBase,
                raw: "http://10.0.0.8:8090/api/v1/stream/already"
            )?.absoluteString,
            "https://silo.example/api/v1/stream/already"
        )
    }

    func testCatalogItemDecodesStringTMDBAndEmptyArtwork() throws {
        let item = try SiloJSON.decoder.decode(SiloCatalogItem.self, from: Data(#"""
        {
          "content_id":"movie:heat-1995",
          "play_content_id":"movie:heat-1995",
          "type":"movie",
          "title":"Heat",
          "tmdb_id":"949",
          "poster_url":"",
          "backdrop_url":"",
          "versions":[{"file_id":"77"}]
        }
        """#.utf8))
        XCTAssertEqual(item.contentID, "movie:heat-1995")
        XCTAssertEqual(item.tmdbID, 949)
        XCTAssertNil(item.posterURL)
        XCTAssertEqual(item.versions?.compactMap(\.resolvedFileID), [77])
    }

    func testSeriesCatalogItemUsesPlayContentID() throws {
        let item = try SiloJSON.decoder.decode(SiloCatalogItem.self, from: Data(#"""
        {
          "content_id":"series:severance",
          "play_content_id":"episode:severance-s02e01",
          "type":"series",
          "title":"Severance",
          "tmdb_id":"95396"
        }
        """#.utf8))
        XCTAssertEqual(item.playbackID, "episode:severance-s02e01")
        XCTAssertFalse(item.isDirectlyPlayable)
    }

    func testWatchProblemJSONMarksInvalidTarget() {
        let error = SiloJSON.error(
            statusCode: 400,
            data: Data(#"""
            {"type":"https://silo.test/problems/invalid_watch_target","title":"Content is not directly playable","status":400}
            """#.utf8)
        )
        XCTAssertTrue(error.isInvalidWatchTarget)
    }

    func testSessionRevokedBodyParsesStringErrorField() {
        // Silo auth endpoints send `error` as a bare string, not an object.
        // This used to fail decoding entirely, leaving code nil and the raw
        // JSON in the message.
        let error = SiloJSON.error(
            statusCode: 401,
            data: Data(#"""
            {"error":"session_revoked","message":"Session has been revoked"}
            """#.utf8)
        )
        XCTAssertEqual(error.code, "session_revoked")
        XCTAssertEqual(error.message, "Session has been revoked")
        XCTAssertTrue(error.isSessionRevoked)
    }

    func testObjectErrorFieldStillParses() {
        // Endpoints that send `error` as an object must keep working.
        let error = SiloJSON.error(
            statusCode: 409,
            data: Data(#"""
            {"error":{"code":"capability_missing","message":"Not configured"}}
            """#.utf8)
        )
        XCTAssertEqual(error.code, "capability_missing")
        XCTAssertEqual(error.message, "Not configured")
        XCTAssertFalse(error.isSessionRevoked)
    }

    func testOrdinaryUnauthorizedIsNotSessionRevoked() {
        let error = SiloJSON.error(
            statusCode: 401,
            data: Data(#"""
            {"error":"forbidden","message":"This profile cannot search subtitles"}
            """#.utf8)
        )
        XCTAssertFalse(error.isSessionRevoked)
    }

    func testQualityResolutionMapsLabelsAndDimensions() {
        XCTAssertEqual(SiloQuality.videoResolution(from: summary(resolution: "2160p")), .fourK)
        XCTAssertEqual(SiloQuality.videoResolution(from: summary(resolution: "UHD")), .fourK)
        XCTAssertEqual(SiloQuality.videoResolution(from: summary(resolution: "1080p")), .hd)
        XCTAssertEqual(SiloQuality.videoResolution(from: summary(resolution: "720p")), .hd)
        XCTAssertEqual(SiloQuality.videoResolution(from: summary(resolution: "480p")), .sd)
        XCTAssertEqual(SiloQuality.videoResolution(from: nil), .unknown)
        // Falls back to file dimensions when the label is absent.
        XCTAssertEqual(
            SiloQuality.videoResolution(from: nil, fallbackWidth: 3840, fallbackHeight: 2160),
            .fourK
        )
    }

    func testQualityVideoRangeMapsHDRStrings() {
        XCTAssertEqual(SiloQuality.videoRange(from: summary(hdr: "DV")), .dolbyVision)
        XCTAssertEqual(SiloQuality.videoRange(from: summary(hdr: "Dolby Vision")), .dolbyVision)
        XCTAssertEqual(SiloQuality.videoRange(from: summary(hdr: "HDR10+")), .hdr10Plus)
        XCTAssertEqual(SiloQuality.videoRange(from: summary(hdr: "HDR10")), .hdr10)
        XCTAssertEqual(SiloQuality.videoRange(from: summary(hdr: "HDR")), .hdr10)
        XCTAssertEqual(SiloQuality.videoRange(from: summary(hdr: "HLG")), .hlg)
        XCTAssertEqual(SiloQuality.videoRange(from: summary(hdr: "SDR")), .sdr)
        XCTAssertEqual(SiloQuality.videoRange(from: nil), .sdr)
    }

    func testQualityAudioDetectsAtmos() {
        XCTAssertEqual(SiloQuality.audioFormat(from: summary(audio: "Atmos")), .atmos)
        XCTAssertEqual(SiloQuality.audioFormat(from: summary(audio: "Dolby TrueHD Atmos")), .atmos)
        XCTAssertEqual(SiloQuality.audioFormat(from: summary(audio: "DTS-HD MA", audioChannels: "7.1")), .surround)
        XCTAssertEqual(SiloQuality.audioFormat(from: summary(audio: "AAC", audioChannels: "2.0")), .stereo)
        XCTAssertEqual(SiloQuality.audioFormat(from: nil), .unknown)
    }

    func testCatalogItemOverlaySummaryDrivesPosterBadges() throws {
        let item = try SiloJSON.decoder.decode(SiloCatalogItem.self, from: Data(#"""
        {
          "content_id": "movie:dune",
          "type": "movie",
          "title": "Dune",
          "overlay_summary": {
            "resolution": "2160p",
            "hdr": "DV",
            "audio": "Atmos",
            "audio_channels": "7.1"
          }
        }
        """#.utf8))
        let mapped = SiloMapper.mediaItem(from: item)
        XCTAssertEqual(mapped.videoResolution, .fourK)
        XCTAssertEqual(mapped.videoRange, .dolbyVision)
        XCTAssertEqual(mapped.audioFormat, .atmos)
        XCTAssertEqual(
            PosterQualityBadges.badges(for: mapped).map(\.title),
            ["4K", "DV", "Atmos"]
        )
    }

    func testCatalogItemWithoutOverlaySummaryHasNoBadges() throws {
        let item = try SiloJSON.decoder.decode(SiloCatalogItem.self, from: Data(#"""
        {"content_id": "movie:plain", "type": "movie", "title": "Plain"}
        """#.utf8))
        let mapped = SiloMapper.mediaItem(from: item)
        XCTAssertEqual(mapped.videoResolution, .unknown)
        XCTAssertEqual(mapped.videoRange, .sdr)
        XCTAssertEqual(mapped.audioFormat, .unknown)
        XCTAssertTrue(PosterQualityBadges.badges(for: mapped).isEmpty)
    }

    private func summary(
        resolution: String? = nil,
        hdr: String? = nil,
        audio: String? = nil,
        audioChannels: String? = nil
    ) -> SiloOverlaySummary {
        var fields: [String] = []
        if let resolution { fields.append("\"resolution\":\"\(resolution)\"") }
        if let hdr { fields.append("\"hdr\":\"\(hdr)\"") }
        if let audio { fields.append("\"audio\":\"\(audio)\"") }
        if let audioChannels { fields.append("\"audio_channels\":\"\(audioChannels)\"") }
        let json = "{\(fields.joined(separator: ","))}"
        // Force-try in a test helper: the JSON is constructed here and always valid.
        return try! SiloJSON.decoder.decode(SiloOverlaySummary.self, from: Data(json.utf8))
    }

    func testDownloadCapabilityDecodesUsabilityAndQuality() throws {
        let usable = try SiloJSON.decoder.decode(SiloDownloadCapability.self, from: Data(#"""
        {"enabled": true, "download_allowed": true, "quality_presets": ["720p", "original"]}
        """#.utf8))
        XCTAssertTrue(usable.isUsable)
        XCTAssertEqual(usable.preferredQuality, "original")

        let blocked = try SiloJSON.decoder.decode(SiloDownloadCapability.self, from: Data(#"""
        {"enabled": true, "download_allowed": false}
        """#.utf8))
        XCTAssertFalse(blocked.isUsable)
        XCTAssertEqual(blocked.preferredQuality, "original")
    }

    func testDownloadRowReadiness() throws {
        let response = try SiloJSON.decoder.decode(SiloDownloadsResponse.self, from: Data(#"""
        {"downloads": [
          {"id": "d1", "content_id": "movie:one", "status": "preparing", "quality": "original"},
          {"id": "d2", "content_id": "movie:two", "status": "ready", "file_size": 12345},
          {"id": "d3", "content_id": "movie:three", "status": "revoked"}
        ]}
        """#.utf8))
        XCTAssertEqual(response.entries.count, 3)
        XCTAssertFalse(response.entries[0].isReady)
        XCTAssertTrue(response.entries[1].isReady)
        XCTAssertEqual(response.entries[1].fileSize, 12345)
        XCTAssertTrue(response.entries[2].isRevoked)
    }

    func testCreateDownloadRequestEncodesSnakeCase() throws {
        let request = SiloCreateDownloadRequest(contentID: "movie:one", fileID: 42, quality: "original")
        let data = try SiloJSON.encoder.encode(request)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["content_id"] as? String, "movie:one")
        XCTAssertEqual(object?["file_id"] as? Int, 42)
        XCTAssertEqual(object?["quality"] as? String, "original")
    }

    func testSimilarResponseDecodesScoredRefs() throws {
        // The recommendation endpoint returns scored ids, not full items.
        let response = try SiloJSON.decoder.decode(SiloSimilarResponse.self, from: Data(#"""
        {"items": [
          {"media_item_id": "movie:one", "score": 0.94, "reason": "same director"},
          {"media_item_id": "movie:two", "score": 0.81}
        ]}
        """#.utf8))
        XCTAssertEqual(response.entries.map(\.id), ["movie:one", "movie:two"])
        XCTAssertNil(response.entries.first?.inlinedItem)
    }

    func testSimilarResponseToleratesInlinedItems() throws {
        // If a server inlines the whole catalog item, use it directly.
        let response = try SiloJSON.decoder.decode(SiloSimilarResponse.self, from: Data(#"""
        {"results": [
          {"content_id": "movie:three", "type": "movie", "title": "Inlined"}
        ]}
        """#.utf8))
        XCTAssertEqual(response.entries.first?.id, "movie:three")
        XCTAssertEqual(response.entries.first?.inlinedItem?.displayTitle, "Inlined")
    }

    func testWatchDetailScrapesStringFileID() {
        let versions = SiloMediaVersion.versions(from: Data(#"""
        {
          "content_id": "movie:one",
          "type": "movie",
          "title": "Dune",
          "versions": [
            {
              "file_id": "42",
              "file_name": "Dune.mkv",
              "resolution": "1080p",
              "codec_video": "hevc",
              "codec_audio": "aac",
              "container": "mkv"
            }
          ]
        }
        """#.utf8))
        XCTAssertEqual(versions.compactMap(\.resolvedFileID), [42])
    }

    func testWatchDetailKeepsSiloFileVersionPayload() throws {
        let versions = SiloMediaVersion.versions(from: Data(#"""
        {
          "content_id": "movie:one",
          "type": "movie",
          "title": "Movie",
          "versions": [{
            "file_id": "71",
            "resolution": "2160p",
            "codec_video": "hevc",
            "codec_audio": "aac",
            "hdr": false,
            "container": "mkv",
            "file_size": 123,
            "duration_seconds": 90,
            "bitrate": 12,
            "added_at": "2026-09-05T12:00:00.123Z",
            "audio_tracks": [
              {"language":"eng","codec":"eac3","title":"English","layout":"5.1","channels":6,"default":true}
            ],
            "subtitle_tracks": [
              {"index":2,"language":"eng","codec":"srt","title":"English","default":true,"external":false}
            ]
          }],
          "subtitles": []
        }
        """#.utf8))
        XCTAssertEqual(versions.compactMap(\.resolvedFileID), [71])
        XCTAssertEqual(versions.first?.audioMediaTracks.map(\.title), ["English"])
        XCTAssertEqual(versions.first?.subtitleMediaTracks.map(\.id), [2])
        XCTAssertEqual(versions.first?.audioMediaTracks.first?.id, 0)
    }

    func testCatalogVersionsCollectionKeepsAudioAndSubtitleTracks() {
        let versions = SiloMediaVersion.versions(from: Data(#"""
        {
          "items": [{
            "file_id": "88",
            "resolution": "1080p",
            "codec_video": "hevc",
            "codec_audio": "truehd",
            "hdr": false,
            "container": "mkv",
            "file_size": 1,
            "duration": 90,
            "bitrate": 12,
            "added_at": "2026-09-05T12:00:00.123Z",
            "audio_tracks": [
              {"language":"eng","codec":"truehd","title":"TrueHD","layout":"7.1","channels":8,"default":true},
              {"language":"jpn","codec":"aac","title":"Japanese","default":false}
            ],
            "subtitle_tracks": [
              {"index":4,"language":"eng","codec":"hdmv_pgs_subtitle","title":"English","default":false,"forced":false,"hearing_impaired":false,"external":false}
            ]
          }]
        }
        """#.utf8))
        XCTAssertEqual(versions.first?.audioMediaTracks.map(\.title), ["TrueHD", "Japanese"])
        XCTAssertEqual(versions.first?.subtitleMediaTracks.map(\.title), ["English"])
        XCTAssertEqual(versions.first?.audioMediaTracks.first?.id, 0)
        XCTAssertEqual(versions.first?.subtitleMediaTracks.first?.id, 4)
    }

    func testWatchDetailKeepsTracksWhenPlaybackVariantsOnlyHaveFileIDs() {
        let versions = SiloMediaVersion.versions(from: Data(#"""
        {
          "content_id": "movie:one",
          "type": "movie",
          "title": "Movie",
          "versions": [{
            "file_id": "71",
            "resolution": "1080p",
            "codec_video": "hevc",
            "codec_audio": "aac",
            "hdr": false,
            "container": "mkv",
            "file_size": 123,
            "duration_seconds": 90,
            "bitrate": 12,
            "added_at": "2026-09-05T12:00:00.123Z",
            "audio_tracks": [
              {"language":"eng","codec":"aac","title":"English","default":true}
            ],
            "subtitle_tracks": [
              {"index":3,"language":"eng","codec":"subrip","title":"English","default":false,"forced":false,"hearing_impaired":false,"external":false}
            ]
          }],
          "playback_variants": [{
            "default_file_id": "71",
            "parts": [{ "default_file_id": "71" }]
          }],
          "subtitles": []
        }
        """#.utf8))
        XCTAssertEqual(versions.first?.audioMediaTracks.map(\.title), ["English"])
        XCTAssertEqual(versions.first?.subtitleMediaTracks.map(\.id), [3])
    }

    func testCatalogItemResolvesFileIDsFromFilesAndVariants() throws {
        let files = try SiloJSON.decoder.decode(SiloCatalogItem.self, from: Data(#"""
        {
          "content_id": "movie:one",
          "type": "movie",
          "title": "Movie",
          "files": [{"file_id": "88", "hdr": false, "file_size": 100}]
        }
        """#.utf8))
        XCTAssertEqual(files.resolvedFileIDs, [88])
        let variants = try SiloJSON.decoder.decode(SiloCatalogItem.self, from: Data(#"""
        {
          "content_id": "movie:one",
          "type": "movie",
          "title": "Movie",
          "playback_variants": [{"variant_id": "main", "default_file_id": "9", "parts": []}]
        }
        """#.utf8))
        XCTAssertEqual(variants.resolvedFileIDs, [9])
        let scraped = SiloCatalogItem(contentID: "movie:one").withFileIDs(from: Data(#"""
        {"content_id":"movie:one","files":[{"media_file_id":"64"}]}
        """#.utf8))
        XCTAssertEqual(scraped.resolvedFileIDs, [64])
    }

    func testPlaybackVariantsExposeDefaultFileID() {
        let versions = SiloMediaVersion.versions(from: Data(#"""
        {
          "content_id": "movie:one",
          "playback_variants": [
            {
              "variant_id": "main",
              "default_file_id": "9",
              "parts": [
                {"part_index": 1, "default_file_id": "9", "versions": []}
              ]
            }
          ]
        }
        """#.utf8))
        XCTAssertEqual(versions.compactMap(\.resolvedFileID), [9])
    }
}

final class SiloProbeTests: XCTestCase {
    func testReachabilityPrefersSiloHealthName() {
        let health = SiloHealth(status: "ok", serverName: "Living Room", serverID: "1", version: "0.9")
        XCTAssertTrue(health.isReady)
        XCTAssertEqual(health.displayName, "Living Room")
    }
}

final class SiloRequestPluginTests: XCTestCase {
    func testMatchesSeerrAndArrPluginIDs() {
        XCTAssertTrue(SiloRequestSource.matches("silo.requests.seerr", source: .seerr))
        XCTAssertTrue(SiloRequestSource.matches("silo.requests.arr", source: .arr))
        XCTAssertFalse(SiloRequestSource.matches("silo.requests.arr", source: .seerr))
        XCTAssertFalse(SiloRequestSource.matches("silo.requests.seerr", source: .arr))
    }

    func testPrefersArrWhenBothPluginsArePresent() {
        XCTAssertEqual(
            SiloRequestSource.resolved(preferred: .arr, seerr: true, arr: true),
            .arr
        )
        XCTAssertEqual(
            SiloRequestSource.resolved(preferred: .seerr, seerr: true, arr: true),
            .seerr
        )
        XCTAssertEqual(
            SiloRequestSource.resolved(preferred: .arr, seerr: true, arr: false),
            .seerr
        )
    }

    func testDiscoverStaysOnWhenRequestsAreEnabledWithoutAListedPlugin() {
        XCTAssertTrue(
            SiloRequestSource.discoverAvailable(
                requestsEnabled: true,
                seerr: false,
                arr: false,
                preferred: .seerr
            )
        )
        XCTAssertFalse(
            SiloRequestSource.discoverAvailable(
                requestsEnabled: false,
                seerr: true,
                arr: true,
                preferred: .seerr
            )
        )
    }

    func testRequestCardMapsSeriesAndAvailability() throws {
        let result = try SiloJSON.decoder.decode(SiloRequestMediaResult.self, from: Data(#"""
        {
          "media_type": "series",
          "tmdb_id": "1396",
          "title": "Breaking Bad",
          "year": 2008,
          "poster_path": "/poster.jpg",
          "availability": "missing",
          "request": { "status": "pending", "requestable": false }
        }
        """#.utf8))
        let title = result.asTitle()
        XCTAssertEqual(title?.kind, .tv)
        XCTAssertEqual(title?.tmdbID, 1396)
        XCTAssertEqual(title?.availability, .pending)
        XCTAssertEqual(title?.posterURL?.absoluteString, "https://image.tmdb.org/t/p/w342/poster.jpg")
    }
}

final class SiloDetailMetadataTests: XCTestCase {
    func testItemDetailMapsRatingsGenresCastAndMoreInfo() throws {
        let item = try SiloJSON.decoder.decode(SiloCatalogItem.self, from: Data(#"""
        {
          "content_id": "show-1",
          "type": "series",
          "title": "Wonder Egg Priority",
          "year": 2021,
          "runtime": 23,
          "genres": ["Horror", "Fantasy"],
          "content_rating": "TV-14",
          "overview": "Ai buys an egg.",
          "original_title": "ワンダーエッグ・プライオリティ",
          "release_date": "2021-01-13",
          "studios": ["CloverWorks"],
          "rating_imdb": 7.4,
          "rating_tmdb": 8.1,
          "rating_rt_critic": 100,
          "rating_rt_audience": 94,
          "imdb_id": "tt1234567",
          "tmdb_id": "96677",
          "cast": [
            {
              "person_id": "p1",
              "name": "Tomori Kusunoki",
              "character": "Ai Ohto",
              "order": 0,
              "photo_url": "https://example.com/ai.jpg"
            }
          ],
          "crew": [{ "person_id": "p2", "name": "Shin Wakabayashi", "job": "Director" }],
          "videos": [
            {
              "kind": "trailer",
              "site": "youtube",
              "site_key": "abc123",
              "name": "Official Trailer",
              "is_official": true
            }
          ]
        }
        """#.utf8))
        let mapped = SiloMapper.mediaItem(from: item)
        XCTAssertEqual(mapped.genres, ["Horror", "Fantasy"])
        XCTAssertEqual(mapped.officialRating, "TV-14")
        XCTAssertEqual(mapped.communityRating, 7.4)
        XCTAssertEqual(mapped.criticRating, 100)
        XCTAssertEqual(mapped.ageGateLabel, "13+")

        let credits = SiloMapper.credits(from: item)
        XCTAssertEqual(credits.map(\.name), ["Tomori Kusunoki", "Shin Wakabayashi"])
        XCTAssertEqual(credits.first?.imageURL?.absoluteString, "https://example.com/ai.jpg")
        XCTAssertEqual(credits.first?.id, "p1")
        XCTAssertEqual(credits.last?.roleLabel, "Director")

        let info = SiloMapper.moreInfo(from: item)
        XCTAssertTrue(info.information.contains(where: { $0.label == "Genres" && $0.value.contains("Horror") }))
        XCTAssertTrue(info.information.contains(where: { $0.label == "Studio" && $0.value == "CloverWorks" }))
        XCTAssertTrue(info.information.contains(where: { $0.label == "Original Title" }))
        XCTAssertEqual(info.links.map(\.name), ["IMDb", "TMDB"])

        let trailers = SiloMapper.trailers(from: item)
        XCTAssertEqual(trailers.first?.id, "youtube-abc123")
        if case .youtube("abc123") = trailers.first?.kind {} else {
            XCTFail("expected a YouTube trailer")
        }
    }

    func testSeasonsSurviveEmptyPosterURLs() throws {
        let response = try SiloJSON.decoder.decode(SiloSeasonsResponse.self, from: Data(#"""
        {
          "seasons": [
            {
              "content_id": "s1",
              "season_number": 1,
              "title": "Season 1",
              "episode_count": 12,
              "poster_url": ""
            },
            {
              "content_id": "s0",
              "season_number": 0,
              "is_specials": true,
              "poster_url": "https://example.com/specials.jpg"
            }
          ]
        }
        """#.utf8))
        XCTAssertEqual(response.entries.count, 2)
        let specials = SiloMapper.season(from: response.entries[1], seriesID: "show-1", seriesTitle: "Show")
        XCTAssertEqual(specials?.name, "Specials")
        XCTAssertEqual(specials?.seasonIndex, 0)
    }

    func testEpisodesMapStillURLAndUserData() throws {
        let response = try SiloJSON.decoder.decode(SiloEpisodesResponse.self, from: Data(#"""
        {
          "episodes": [
            {
              "content_id": "e1",
              "season_number": 1,
              "episode_number": 2,
              "title": "The Witch",
              "overview": "Ai meets Neiru.",
              "runtime": 23,
              "still_url": "https://example.com/still.jpg",
              "user_data": { "played": false, "position_seconds": 80 }
            }
          ]
        }
        """#.utf8))
        let episode = try XCTUnwrap(response.entries.first)
        let mapped = try XCTUnwrap(SiloMapper.mediaItem(from: episode, seriesID: "show-1", seriesTitle: "Show"))
        XCTAssertEqual(mapped.name, "The Witch")
        XCTAssertEqual(mapped.seasonIndex, 1)
        XCTAssertEqual(mapped.episodeIndex, 2)
        XCTAssertEqual(mapped.playbackPosition, 80)
        XCTAssertEqual(mapped.posterURL?.absoluteString, "https://example.com/still.jpg")
        XCTAssertEqual(mapped.overview, "Ai meets Neiru.")
    }

    func testV2EpisodeCollectionItemsEnvelope() throws {
        let response = try SiloJSON.decoder.decode(SiloEpisodesResponse.self, from: Data(#"""
        {
          "items": [
            {
              "content_id": "episode:rafa-s01e01",
              "season_number": 1,
              "episode_number": 1,
              "title": "Pilot",
              "overview": "",
              "runtime": 28,
              "still_url": "",
              "files": [{ "file_id": "12", "hdr": false, "file_size": 100 }],
              "user_data": {
                "played": false,
                "in_progress_count": 0,
                "unplayed_count": 1,
                "watched_count": 0,
                "position_seconds": 0
              }
            }
          ]
        }
        """#.utf8))
        XCTAssertEqual(response.entries.count, 1)
        let mapped = try XCTUnwrap(
            SiloMapper.mediaItem(from: response.entries[0], seriesID: "show-1", seriesTitle: "Show")
        )
        XCTAssertEqual(mapped.id, "episode:rafa-s01e01")
        XCTAssertEqual(mapped.name, "Pilot")
        XCTAssertEqual(mapped.seasonIndex, 1)
        XCTAssertEqual(mapped.episodeIndex, 1)
        XCTAssertNil(mapped.posterURL)
        XCTAssertEqual(response.entries[0].resolvedFileID, 12)
    }
}
