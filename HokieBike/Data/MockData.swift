import Foundation
import SwiftUI
import Combine
import CoreLocation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

#if canImport(FirebaseStorage)
import FirebaseStorage
#endif

/// Simple in-memory app state + mock data provider
@MainActor
final class AppViewModel: ObservableObject {
    private let demoBikeAnchorName = "Burruss Hall"
    private let demoBikeAnchorCoordinate = CLLocationCoordinate2D(latitude: 37.2291, longitude: -80.4235)

    @Published var bikes: [Bike] = []
    @Published var journeys: [Journey] = []
    @Published var rentalsHistory: [Rental] = []
    @Published var activeRental: Rental?
    @Published var currentUser: User

    @Published var savedJourneyIDs: Set<UUID> = []
    @Published var savedBikeIDs: Set<UUID> = []
    @Published var selectedJourneyCategory: JourneyCategory = .all
    @Published var myJourneyIDs: Set<UUID> = []
    @Published var didFinishInitialProfileLoad = false

    @Published var communityPosts: [CommunityPost] = []
    @Published var lastSyncStatus: String = "Idle"
    @Published var lastSyncAt: Date?
    @Published var lastSyncError: String?
    @Published var latestRideSnapshotID: String?
    @Published var routePathByRentalID: [UUID: [CLLocationCoordinate2D]] = [:]

    private var backendUID: String?
    private var backendEmail: String?
#if canImport(FirebaseFirestore)
    private var communityPostsListener: ListenerRegistration?
#endif

    var backendUIDForDiagnostics: String {
        backendUID ?? "Not signed in"
    }

    init() {
        currentUser = User(name: "", isVTStudent: true, rentalsCount: 0, bikesListed: 0)
        loadSampleData()
    }

    func configureBackendSession(uid: String, email: String) {
        backendUID = uid
        backendEmail = email
        lastSyncStatus = "Connecting backend..."
        lastSyncError = nil
        didFinishInitialProfileLoad = false
        Task {
            await loadUserProfileIfExists(uid: uid, fallbackEmail: email)
            await loadJourneysFromBackend()
            await loadRentalsFromBackend(uid: uid)
            await loadCommunityPostsFromBackend(uid: uid)
            startCommunityPostsListener()
            await upsertCurrentUserProfile()
            await persistResearchEvent(eventType: "pilot_session_started", details: [:])
            markSyncSuccess("Backend connected")
            await MainActor.run {
                didFinishInitialProfileLoad = true
            }
        }
    }

    func clearBackendSession() {
        backendUID = nil
        backendEmail = nil
        myJourneyIDs = []
        didFinishInitialProfileLoad = false
        lastSyncStatus = "Signed out"
        lastSyncError = nil
        latestRideSnapshotID = nil
        stopCommunityPostsListener()
    }

    func runSyncDiagnostics() {
        Task {
            guard let uid = backendUID else {
                markSyncFailure("Manual sync check failed", error: NSError(domain: "HokieBike", code: 401, userInfo: [NSLocalizedDescriptionKey: "No authenticated backend session."]))
                return
            }

            await loadRentalsFromBackend(uid: uid)
            await loadCommunityPostsFromBackend(uid: uid)
            await upsertCurrentUserProfile()
            await loadJourneysFromBackend()
            markSyncSuccess("Manual sync check completed")
        }
    }

    func loadSampleData() {
        bikes = [
            Bike(
                name: "DemoBike",
                type: "Hybrid",
                ownerName: "HokieBike Team",
                description: "Our real demo bike on campus. Tap into the bike to unlock over Bluetooth and start your ride.",
                pricePerHour: 5.00,
                location: demoBikeAnchorName,
                isAvailable: true,
                imageName: "HokieBikeDemoBike",
                usesAssetImage: true,
                latitude: demoBikeAnchorCoordinate.latitude,
                longitude: demoBikeAnchorCoordinate.longitude,
                lastSeenAt: Date().addingTimeInterval(-1800),
                lastSeenSource: "ride_end"
            )
        ]

        journeys = [
            Journey(title: "Duck Pond Cruise", subtitle: "Virginia Tech Campus", description: "A relaxing campus ride to the Duck Pond with scenic paths and calm traffic.", startName: "Drillfield", destinationName: "Virginia Tech Duck Pond", startLatitude: 37.2277, startLongitude: -80.4232, destinationLatitude: 37.2259, destinationLongitude: -80.4267, difficulty: "Easy", category: .campus, imageName: "JourneyDuckPond", usesAssetImage: true),
            Journey(title: "Lane Stadium Loop", subtitle: "Virginia Tech Campus", description: "A short ride around campus ending near Lane Stadium.", startName: "Squires Student Center", destinationName: "Lane Stadium", startLatitude: 37.2299, startLongitude: -80.4178, destinationLatitude: 37.2209, destinationLongitude: -80.4185, difficulty: "Easy", category: .exercise, imageName: "JourneyLaneStadium", usesAssetImage: true),
            Journey(title: "Downtown Blacksburg Route", subtitle: "Blacksburg", description: "Ride from campus into downtown Blacksburg for coffee and local spots.", startName: "Newman Library", destinationName: "Downtown Blacksburg", startLatitude: 37.2285, startLongitude: -80.4214, destinationLatitude: 37.2296, destinationLongitude: -80.4139, difficulty: "Moderate", category: .scenic, imageName: "JourneyDowntownBlacksburg", usesAssetImage: true),
            Journey(title: "Huckleberry Intro", subtitle: "Blacksburg to Christiansburg", description: "A beginner-friendly segment on the Huckleberry Trail toward Christiansburg.", startName: "Heritage Community Park", destinationName: "Uptown Christiansburg", startLatitude: 37.2441, startLongitude: -80.4311, destinationLatitude: 37.1298, destinationLongitude: -80.4089, difficulty: "Moderate", category: .beginner, imageName: "JourneyHuckleberry", usesAssetImage: true),
            Journey(title: "Gateway Park Ride", subtitle: "Blacksburg", description: "Longer scenic ride connecting campus-adjacent roads to Gateway Park.", startName: "Torgersen Hall", destinationName: "Gateway Park", startLatitude: 37.2297, startLongitude: -80.4195, destinationLatitude: 37.2397, destinationLongitude: -80.4058, difficulty: "Hard", category: .longerRides, imageName: "JourneyGatewayPark", usesAssetImage: true),
            Journey(title: "Coal Mining Heritage Visit", subtitle: "Christiansburg", description: "Community favorite destination to explore local history and parks.", startName: "Drillfield", destinationName: "Coal Mining Heritage Park", startLatitude: 37.2277, startLongitude: -80.4232, destinationLatitude: 37.1301, destinationLongitude: -80.4219, difficulty: "Hard", category: .community, imageName: "JourneyCoalMining", usesAssetImage: true)
        ]
        rentalsHistory = []

        communityPosts = [
            CommunityPost(
                authorName: "Example Rider",
                journeyTitle: "Example Post: Campus Spin",
                bodyText: "Example post for demo: Shared route, pace, and ride notes.",
                likes: 3,
                comments: [PostComment(authorName: "Example Commenter", text: "Example comment for reference.")]
            )
        ]
    }

    var filteredJourneys: [Journey] {
        if selectedJourneyCategory == .all {
            return journeys
        }
        return journeys.filter { $0.category == selectedJourneyCategory }
    }

    var completedRentals: [Rental] {
        rentalsHistory.filter { !$0.isActive }
    }

    var totalDistanceKm: Double {
        completedRentals.compactMap(\.distanceMeters).reduce(0, +) / 1000.0
    }

    var totalDistanceMiles: Double {
        totalDistanceKm * 0.621371
    }

    var averageSpeedKph: Double {
        let totalSeconds = completedRentals.reduce(0.0) { $0 + $1.duration }
        guard totalSeconds > 0 else { return 0 }
        return totalDistanceKm / (totalSeconds / 3600.0)
    }

    var averageSpeedMph: Double {
        averageSpeedKph * 0.621371
    }

    var estimatedCO2SavedKg: Double {
        // Approx passenger vehicle emissions: ~0.404 kg CO2 per mile avoided.
        totalDistanceMiles * 0.404
    }

    var mostRecentCompletedRental: Rental? {
        completedRentals.sorted(by: { $0.startDate > $1.startDate }).first
    }

    // MARK: - Saved content
    func toggleJourneySaved(_ journey: Journey) {
        if savedJourneyIDs.contains(journey.id) {
            savedJourneyIDs.remove(journey.id)
        } else {
            savedJourneyIDs.insert(journey.id)
        }
    }

    func toggleBikeSaved(_ bike: Bike) {
        if savedBikeIDs.contains(bike.id) {
            savedBikeIDs.remove(bike.id)
        } else {
            savedBikeIDs.insert(bike.id)
        }
    }

    func isJourneySaved(_ journey: Journey) -> Bool {
        savedJourneyIDs.contains(journey.id)
    }

    func isBikeSaved(_ bike: Bike) -> Bool {
        savedBikeIDs.contains(bike.id)
    }

    // MARK: - Community posts
    func createPost(journeyTitle: String, bodyText: String, imageData: Data?) {
        let post = CommunityPost(
            authorName: currentUser.name,
            authorID: backendUID,
            journeyTitle: journeyTitle,
            bodyText: bodyText,
            attachedRentalID: mostRecentCompletedRental?.id,
            likes: 0,
            isLikedByCurrentUser: false,
            likedUserIDs: [],
            comments: [],
            imageData: imageData,
            photoURL: nil
        )
        communityPosts.insert(post, at: 0)

        Task {
            await persistCommunityPost(post)
            await upsertCurrentUserProfile()
        }
    }

    func deletePost(postID: UUID) {
        communityPosts.removeAll { $0.id == postID }
        Task {
            await deleteCommunityPostFromBackend(postID: postID)
        }
    }

    func deleteRental(rentalID: UUID) {
        guard rentalsHistory.contains(where: { $0.id == rentalID }) else { return }

        let attachedPostIDs = communityPosts
            .filter { $0.attachedRentalID == rentalID && $0.authorName == currentUser.name }
            .map(\.id)

        rentalsHistory.removeAll { $0.id == rentalID }
        communityPosts.removeAll { attachedPostIDs.contains($0.id) }
        currentUser.rentalsCount = max(0, currentUser.rentalsCount - 1)

        if latestRideSnapshotID == rentalID.uuidString {
            latestRideSnapshotID = nil
        }

        Task {
            for postID in attachedPostIDs {
                await deleteCommunityPostFromBackend(postID: postID)
            }
            await deleteRentalFromBackend(rentalID: rentalID)
            await upsertCurrentUserProfile()
        }
    }

    func toggleLike(postID: UUID) {
        guard let idx = communityPosts.firstIndex(where: { $0.id == postID }) else { return }

        guard let uid = backendUID else {
            // Local fallback for unauthenticated sessions.
            communityPosts[idx].isLikedByCurrentUser.toggle()
            communityPosts[idx].likes += communityPosts[idx].isLikedByCurrentUser ? 1 : -1
            communityPosts[idx].likes = max(0, communityPosts[idx].likes)
            return
        }

        if communityPosts[idx].likedUserIDs.isEmpty {
            // Legacy docs without per-user like sets.
            communityPosts[idx].isLikedByCurrentUser.toggle()
            communityPosts[idx].likes += communityPosts[idx].isLikedByCurrentUser ? 1 : -1
            communityPosts[idx].likes = max(0, communityPosts[idx].likes)
        } else {
            if communityPosts[idx].likedUserIDs.contains(uid) {
                communityPosts[idx].likedUserIDs.remove(uid)
            } else {
                communityPosts[idx].likedUserIDs.insert(uid)
            }

            communityPosts[idx].isLikedByCurrentUser = communityPosts[idx].likedUserIDs.contains(uid)
            communityPosts[idx].likes = communityPosts[idx].likedUserIDs.count
        }

        Task {
            await persistPostEngagement(communityPosts[idx])
        }
    }

    func routePath(for rentalID: UUID?) -> [CLLocationCoordinate2D]? {
        guard let rentalID else { return nil }
        return routePathByRentalID[rentalID]
    }

    func addComment(postID: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let idx = communityPosts.firstIndex(where: { $0.id == postID }) else { return }
        communityPosts[idx].comments.append(PostComment(authorName: currentUser.name, text: trimmed))

        Task {
            await persistPostEngagement(communityPosts[idx])
        }
    }

    func updateCurrentUserProfile(name: String, isVTStudent: Bool, profileImageData: Data? = nil, pilotID: String? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        currentUser.name = trimmed
        currentUser.isVTStudent = isVTStudent
        if let pilotID {
            let normalizedPilotID = pilotID.trimmingCharacters(in: .whitespacesAndNewlines)
            currentUser.pilotID = normalizedPilotID.isEmpty ? nil : normalizedPilotID
        }

        Task {
            if let profileImageData {
                await updateProfilePhoto(imageData: profileImageData)
            }
            await upsertCurrentUserProfile()
        }
    }

    func updateProfilePhoto(imageData: Data) async {
#if canImport(FirebaseStorage)
        guard let uid = backendUID else { return }
        if let url = await uploadProfileImageData(imageData, uid: uid) {
            currentUser.profilePhotoURL = url
        }
#endif
    }

    // MARK: - Bike management
    func addBike(name: String, type: String, description: String, pricePerHour: Double, location: String, isAvailable: Bool) {
        let new = Bike(name: name, type: type, ownerName: currentUser.name, description: description, pricePerHour: pricePerHour, location: location, isAvailable: isAvailable)
        bikes.insert(new, at: 0)
        currentUser.bikesListed += 1
        Task {
            await upsertCurrentUserProfile()
        }
    }

    // MARK: - Journey management
    func createJourney(
        title: String,
        subtitle: String,
        description: String,
        startName: String,
        destinationName: String,
        startCoordinate: CLLocationCoordinate2D,
        destinationCoordinate: CLLocationCoordinate2D,
        difficulty: String,
        category: JourneyCategory
    ) {
        let journey = Journey(
            title: title,
            subtitle: subtitle,
            description: description,
            startName: startName,
            destinationName: destinationName,
            startLatitude: startCoordinate.latitude,
            startLongitude: startCoordinate.longitude,
            destinationLatitude: destinationCoordinate.latitude,
            destinationLongitude: destinationCoordinate.longitude,
            difficulty: difficulty,
            category: category,
            imageName: "figure.outdoor.cycle",
            usesAssetImage: false
        )
        journeys.insert(journey, at: 0)
        myJourneyIDs.insert(journey.id)

        Task {
            await persistJourney(journey)
        }
    }

    func canDeleteJourney(_ journey: Journey) -> Bool {
        myJourneyIDs.contains(journey.id)
    }

    func deleteJourney(journeyID: UUID) {
        journeys.removeAll { $0.id == journeyID }
        savedJourneyIDs.remove(journeyID)
        myJourneyIDs.remove(journeyID)

        Task {
            await deleteJourneyFromBackend(journeyID: journeyID)
        }
    }

    func nearbyBikes(around coordinate: CLLocationCoordinate2D, maxDistanceMeters: CLLocationDistance = 1500) -> [Bike] {
        bikes
            .compactMap { bike -> (bike: Bike, distance: CLLocationDistance)? in
                guard let bikeCoordinate = bike.coordinate else { return nil }
                let bikePoint = CLLocation(latitude: bikeCoordinate.latitude, longitude: bikeCoordinate.longitude)
                let point = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                let distance = bikePoint.distance(from: point)
                guard distance <= maxDistanceMeters else { return nil }
                return (bike: bike, distance: distance)
            }
            .sorted(by: { $0.distance < $1.distance })
            .map { $0.bike }
    }

    // MARK: - Rental flow
    func startRental(bike: Bike, startLocation: String? = nil, startCoordinate: CLLocationCoordinate2D? = nil) {
        guard activeRental == nil else { return }
        guard let idx = bikes.firstIndex(where: { $0.id == bike.id }), bikes[idx].isAvailable else { return }

        bikes[idx].isAvailable = false

        let rental = Rental(
            bike: bikes[idx],
            renterName: currentUser.name,
            startDate: Date(),
            startLocation: startLocation,
            startCoordinate: startCoordinate
        )
        activeRental = rental

        Task {
            await persistRentalStart(rental)
        }
    }

    func endRental(
        endLocation: String? = nil,
        endCoordinate: CLLocationCoordinate2D? = nil,
        destinationName: String? = nil,
        trackedPath: [CLLocationCoordinate2D] = []
    ) {
        guard var rental = activeRental else { return }
        rental.endDate = Date()
        rental.endLocation = endLocation
        rental.endLatitude = endCoordinate?.latitude
        rental.endLongitude = endCoordinate?.longitude

        if let idx = bikes.firstIndex(where: { $0.id == rental.bike.id }) {
            bikes[idx].isAvailable = true
            if bikes[idx].name == "DemoBike" {
                // Keep the demo pin stable for launch demos.
                bikes[idx].latitude = demoBikeAnchorCoordinate.latitude
                bikes[idx].longitude = demoBikeAnchorCoordinate.longitude
                bikes[idx].location = demoBikeAnchorName
                bikes[idx].lastSeenAt = Date()
                bikes[idx].lastSeenSource = "demo_anchor"
            } else if let endCoordinate {
                bikes[idx].latitude = endCoordinate.latitude
                bikes[idx].longitude = endCoordinate.longitude
                bikes[idx].lastSeenAt = Date()
                bikes[idx].lastSeenSource = "ride_end"
                if let endLocation, !endLocation.isEmpty {
                    bikes[idx].location = endLocation
                }
            }
        }

        rentalsHistory.insert(rental, at: 0)
        currentUser.rentalsCount += 1
        activeRental = nil

        Task {
            await persistRentalEnd(rental, destinationName: destinationName, trackedPath: trackedPath)
            await upsertCurrentUserProfile()
        }
    }

    private func upsertCurrentUserProfile() async {
#if canImport(FirebaseFirestore)
        guard let uid = backendUID, let email = backendEmail else { return }

        let db = Firestore.firestore()
        let ref = db.collection("users").document(uid)

        let payload: [String: Any] = [
            "email": email,
            "displayName": currentUser.name,
            "isVTStudent": currentUser.isVTStudent,
            "pilotID": currentUser.pilotID ?? "",
            "rentalsCount": currentUser.rentalsCount,
            "bikesListed": currentUser.bikesListed,
            "profilePhotoURL": currentUser.profilePhotoURL ?? "",
            "totalDistanceKm": totalDistanceKm,
            "totalDistanceMiles": totalDistanceMiles,
            "averageSpeedKph": averageSpeedKph,
            "averageSpeedMph": averageSpeedMph,
            "estimatedCO2SavedKg": estimatedCO2SavedKg,
            "updatedAt": Timestamp(date: Date())
        ]

        do {
            try await ref.setData(payload, merge: true)
            await persistResearchEvent(
                eventType: "profile_upsert",
                details: [
                    "rentalsCount": currentUser.rentalsCount,
                    "bikesListed": currentUser.bikesListed,
                    "pilotID": currentUser.pilotID ?? ""
                ]
            )
            markSyncSuccess("Profile synced")
        } catch {
            markSyncFailure("Profile sync failed", error: error)
        }
#endif
    }

    private func loadUserProfileIfExists(uid: String, fallbackEmail: String) async {
#if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let ref = db.collection("users").document(uid)

        do {
            let snapshot = try await ref.getDocument()
            guard let data = snapshot.data(), snapshot.exists else { return }

            let defaultName = fallbackEmail.components(separatedBy: "@").first ?? "Hokie"
            let loadedName = (data["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            currentUser.name = (loadedName?.isEmpty == false) ? loadedName! : defaultName
            currentUser.isVTStudent = data["isVTStudent"] as? Bool ?? true
            currentUser.rentalsCount = data["rentalsCount"] as? Int ?? currentUser.rentalsCount
            currentUser.bikesListed = data["bikesListed"] as? Int ?? currentUser.bikesListed
            currentUser.profilePhotoURL = data["profilePhotoURL"] as? String
            let loadedPilotID = (data["pilotID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            currentUser.pilotID = (loadedPilotID?.isEmpty == false) ? loadedPilotID : nil
            markSyncSuccess("Profile loaded")
        } catch {
            markSyncFailure("Profile load failed", error: error)
        }
#endif
    }

    private func loadRentalsFromBackend(uid: String) async {
#if canImport(FirebaseFirestore)
        let db = Firestore.firestore()

        do {
            let snapshot = try await db.collection("rentals")
                .whereField("userId", isEqualTo: uid)
                .limit(to: 500)
                .getDocuments()

            let loaded: [Rental] = snapshot.documents.compactMap { doc in
                let data = doc.data()
                let rentalID = UUID(uuidString: data["rentalId"] as? String ?? "") ?? UUID(uuidString: doc.documentID) ?? UUID()
                let bikeID = UUID(uuidString: data["bikeId"] as? String ?? "") ?? UUID()
                let bikeName = data["bikeName"] as? String ?? "HokieBike"
                let pricePerHour = data["pricePerHour"] as? Double ?? 5.0
                let startDate = (data["startAt"] as? Timestamp)?.dateValue() ?? Date()
                let renterName = currentUser.name.isEmpty ? "Hokie Rider" : currentUser.name

                var rental = Rental(
                    id: rentalID,
                    bike: Bike(
                        id: bikeID,
                        name: bikeName,
                        type: data["bikeType"] as? String ?? "Bike",
                        ownerName: "HokieBike Team",
                        description: "",
                        pricePerHour: pricePerHour,
                        location: data["startLocation"] as? String ?? "Unknown",
                        isAvailable: (data["status"] as? String ?? "completed") != "active"
                    ),
                    renterName: renterName,
                    startDate: startDate,
                    startLocation: data["startLocation"] as? String,
                    startCoordinate: {
                        if let lat = data["startLat"] as? Double, let lng = data["startLng"] as? Double {
                            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
                        }
                        return nil
                    }()
                )

                rental.endDate = (data["endAt"] as? Timestamp)?.dateValue()
                rental.endLocation = data["endLocation"] as? String
                rental.endLatitude = data["endLat"] as? Double
                rental.endLongitude = data["endLng"] as? Double
                return rental
            }
            .sorted(by: { $0.startDate > $1.startDate })

            rentalsHistory = loaded.filter { !$0.isActive }
            activeRental = loaded.first(where: { $0.isActive })
            markSyncSuccess("Rentals loaded")
        } catch {
            markSyncFailure("Rental load failed", error: error)
        }
#endif
    }

    private func persistResearchEvent(eventType: String, details: [String: Any]) async {
#if canImport(FirebaseFirestore)
        guard let uid = backendUID else { return }
        let db = Firestore.firestore()

        var payload: [String: Any] = [
            "eventType": eventType,
            "userId": uid,
            "pilotID": currentUser.pilotID ?? "",
            "createdAt": Timestamp(date: Date()),
            "details": details
        ]

        if let latestRideSnapshotID {
            payload["latestRideSnapshotID"] = latestRideSnapshotID
        }

        do {
            _ = try await db.collection("research_events").addDocument(data: payload)
        } catch {
            markSyncFailure("Research event sync failed", error: error)
        }
#endif
    }

    private func persistRentalStart(_ rental: Rental) async {
#if canImport(FirebaseFirestore)
        guard let uid = backendUID else { return }

        let db = Firestore.firestore()
        let ref = db.collection("rentals").document(rental.id.uuidString)

        var payload: [String: Any] = [
            "rentalId": rental.id.uuidString,
            "userId": uid,
            "pilotID": currentUser.pilotID ?? "",
            "bikeId": rental.bike.id.uuidString,
            "bikeName": rental.bike.name,
            "pricePerHour": rental.bike.pricePerHour,
            "status": "active",
            "startAt": Timestamp(date: rental.startDate),
            "startLocation": rental.startLocation ?? rental.bike.location,
            "updatedAt": Timestamp(date: Date())
        ]

        if let startLatitude = rental.startLatitude, let startLongitude = rental.startLongitude {
            payload["startLat"] = startLatitude
            payload["startLng"] = startLongitude
        }

        do {
            try await ref.setData(payload, merge: true)
            await persistResearchEvent(
                eventType: "rental_started",
                details: [
                    "rentalId": rental.id.uuidString,
                    "bikeId": rental.bike.id.uuidString
                ]
            )
            markSyncSuccess("Rental start synced")
        } catch {
            markSyncFailure("Rental start sync failed", error: error)
        }
#endif
    }

    private func persistRentalEnd(_ rental: Rental, destinationName: String?, trackedPath: [CLLocationCoordinate2D]) async {
#if canImport(FirebaseFirestore)
        guard let uid = backendUID else { return }

        let db = Firestore.firestore()
        let ref = db.collection("rentals").document(rental.id.uuidString)

        var payload: [String: Any] = [
            "status": "completed",
            "pilotID": currentUser.pilotID ?? "",
            "endAt": Timestamp(date: rental.endDate ?? Date()),
            "endLocation": rental.endLocation ?? "",
            "durationSeconds": rental.duration,
            "cost": rental.cost(),
            "updatedAt": Timestamp(date: Date())
        ]

        if let endLatitude = rental.endLatitude, let endLongitude = rental.endLongitude {
            payload["endLat"] = endLatitude
            payload["endLng"] = endLongitude
        }

        if let distanceMeters = rental.distanceMeters {
            payload["distanceMeters"] = distanceMeters
        }

        if let destinationName, !destinationName.isEmpty {
            payload["destinationName"] = destinationName
        }

        if !trackedPath.isEmpty {
            payload["trackedPath"] = trackedPath.map { ["lat": $0.latitude, "lng": $0.longitude] }
        }

        do {
            try await ref.setData(payload, merge: true)
            await persistRideSnapshot(
                uid: uid,
                rental: rental,
                destinationName: destinationName,
                trackedPath: trackedPath
            )
            await persistResearchEvent(
                eventType: "rental_completed",
                details: [
                    "rentalId": rental.id.uuidString,
                    "durationSeconds": rental.duration,
                    "cost": rental.cost(),
                    "distanceMeters": rental.distanceMeters ?? 0
                ]
            )
            markSyncSuccess("Rental end synced")
        } catch {
            markSyncFailure("Rental end sync failed", error: error)
        }
#endif
    }

    private func persistRideSnapshot(
        uid: String,
        rental: Rental,
        destinationName: String?,
        trackedPath: [CLLocationCoordinate2D]
    ) async {
#if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let ref = db.collection("ride_snapshots").document(rental.id.uuidString)

        let sampledPath = samplePath(trackedPath, maxPoints: 60)
        let startLat = rental.startLatitude
        let startLng = rental.startLongitude
        let endLat = rental.endLatitude
        let endLng = rental.endLongitude

        var payload: [String: Any] = [
            "snapshotId": rental.id.uuidString,
            "userId": uid,
            "pilotID": currentUser.pilotID ?? "",
            "bikeId": rental.bike.id.uuidString,
            "bikeName": rental.bike.name,
            "bikeType": rental.bike.type,
            "isDemoBike": rental.bike.name == "DemoBike",
            "startedAt": Timestamp(date: rental.startDate),
            "endedAt": Timestamp(date: rental.endDate ?? Date()),
            "durationSeconds": rental.duration,
            "cost": rental.cost(),
            "destinationName": destinationName ?? "",
            "trackedPointCount": trackedPath.count,
            "trackedPathSample": sampledPath,
            "totalDistanceKmAfterRide": totalDistanceKm,
            "totalDistanceMilesAfterRide": totalDistanceMiles,
            "averageSpeedKphAfterRide": averageSpeedKph,
            "averageSpeedMphAfterRide": averageSpeedMph,
            "estimatedCO2SavedKgAfterRide": estimatedCO2SavedKg,
            "completedRideCountAfterRide": currentUser.rentalsCount,
            "createdAt": Timestamp(date: Date())
        ]

        if let distanceMeters = rental.distanceMeters {
            payload["distanceMeters"] = distanceMeters
        }

        if let startLat, let startLng {
            payload["startLat"] = startLat
            payload["startLng"] = startLng
        }

        if let endLat, let endLng {
            payload["endLat"] = endLat
            payload["endLng"] = endLng
        }

        let bounds = routeBounds(for: trackedPath)
        if let minLat = bounds.minLat, let maxLat = bounds.maxLat, let minLng = bounds.minLng, let maxLng = bounds.maxLng {
            payload["bounds"] = [
                "minLat": minLat,
                "maxLat": maxLat,
                "minLng": minLng,
                "maxLng": maxLng
            ]
        }

        do {
            try await ref.setData(payload, merge: true)
            latestRideSnapshotID = rental.id.uuidString
            markSyncSuccess("Ride snapshot synced")
        } catch {
            markSyncFailure("Ride snapshot sync failed", error: error)
        }
#endif
    }

    private func persistCommunityPost(_ post: CommunityPost) async {
#if canImport(FirebaseFirestore)
        guard let uid = backendUID else { return }

        let db = Firestore.firestore()
        let ref = db.collection("posts").document(post.id.uuidString)

        var imageURLString = post.photoURL ?? ""
        var imageBase64String = ""
#if canImport(FirebaseStorage)
        if let imageData = post.imageData {
            imageURLString = await uploadPostImageData(imageData, postID: post.id) ?? ""
            if imageURLString.isEmpty, let compressed = compressedJPEGData(from: imageData) {
                imageBase64String = compressed.base64EncodedString()
            }
        }
#else
        if let imageData = post.imageData, let compressed = compressedJPEGData(from: imageData) {
            imageBase64String = compressed.base64EncodedString()
        }
#endif

        let payload: [String: Any] = [
            "postId": post.id.uuidString,
            "authorId": post.authorID ?? uid,
            "pilotID": currentUser.pilotID ?? "",
            "authorName": post.authorName,
            "journeyTitle": post.journeyTitle,
            "bodyText": post.bodyText,
            "attachedRentalId": post.attachedRentalID?.uuidString ?? "",
            "likes": post.likes,
            "likedUserIDs": Array(post.likedUserIDs),
            "isLikedByCurrentUser": post.isLikedByCurrentUser,
            "comments": post.comments.map {
                [
                    "id": $0.id.uuidString,
                    "authorName": $0.authorName,
                    "text": $0.text,
                    "createdAt": Timestamp(date: $0.createdAt)
                ]
            },
            "photoURL": imageURLString,
            "imageBase64": imageBase64String,
            "createdAt": Timestamp(date: post.createdAt),
            "updatedAt": Timestamp(date: Date())
        ]

        do {
            try await ref.setData(payload, merge: true)
            await persistResearchEvent(
                eventType: "post_upsert",
                details: [
                    "postId": post.id.uuidString,
                    "likes": post.likes,
                    "commentsCount": post.comments.count
                ]
            )
            markSyncSuccess("Post synced")
        } catch {
            markSyncFailure("Post sync failed", error: error)
        }
#endif
    }



    private func persistPostEngagement(_ post: CommunityPost) async {
#if canImport(FirebaseFirestore)
        guard backendUID != nil else { return }
        let db = Firestore.firestore()
        let ref = db.collection("posts").document(post.id.uuidString)

        let payload: [String: Any] = [
            "likes": post.likes,
            "isLikedByCurrentUser": post.isLikedByCurrentUser,
            "comments": post.comments.map {
                [
                    "id": $0.id.uuidString,
                    "authorName": $0.authorName,
                    "text": $0.text,
                    "createdAt": Timestamp(date: $0.createdAt)
                ]
            },
            "updatedAt": Timestamp(date: Date())
        ]

        do {
            try await ref.setData(payload, merge: true)
            markSyncSuccess("Post engagement synced")
        } catch {
            markSyncFailure("Post engagement sync failed", error: error)
        }
#endif
    }
    private func deleteCommunityPostFromBackend(postID: UUID) async {
#if canImport(FirebaseFirestore)
        guard backendUID != nil else { return }
        let db = Firestore.firestore()
        do {
            try await db.collection("posts").document(postID.uuidString).delete()
            await persistResearchEvent(eventType: "post_deleted", details: ["postId": postID.uuidString])
            markSyncSuccess("Post deleted")
        } catch {
            markSyncFailure("Post delete failed", error: error)
        }

#if canImport(FirebaseStorage)
        let storageRef = Storage.storage().reference().child("posts/\(postID.uuidString).jpg")
        _ = try? await storageRef.delete()
#endif
#endif
    }

    private func persistJourney(_ journey: Journey) async {
#if canImport(FirebaseFirestore)
        guard let uid = backendUID else { return }

        let db = Firestore.firestore()
        let ref = db.collection("journeys").document(journey.id.uuidString)

        let payload: [String: Any] = [
            "journeyId": journey.id.uuidString,
            "authorId": uid,
            "pilotID": currentUser.pilotID ?? "",
            "title": journey.title,
            "subtitle": journey.subtitle,
            "description": journey.description,
            "startName": journey.startName,
            "destinationName": journey.destinationName,
            "startLat": journey.startLatitude,
            "startLng": journey.startLongitude,
            "destinationLat": journey.destinationLatitude,
            "destinationLng": journey.destinationLongitude,
            "difficulty": journey.difficulty,
            "category": journey.category.rawValue,
            "imageName": journey.imageName,
            "usesAssetImage": journey.usesAssetImage,
            "createdAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date())
        ]

        do {
            try await ref.setData(payload, merge: true)
            await persistResearchEvent(
                eventType: "journey_upsert",
                details: [
                    "journeyId": journey.id.uuidString,
                    "category": journey.category.rawValue
                ]
            )
            markSyncSuccess("Journey synced")
        } catch {
            markSyncFailure("Journey sync failed", error: error)
        }
#endif
    }

    private func deleteJourneyFromBackend(journeyID: UUID) async {
#if canImport(FirebaseFirestore)
        guard backendUID != nil else { return }
        let db = Firestore.firestore()
        do {
            try await db.collection("journeys").document(journeyID.uuidString).delete()
            await persistResearchEvent(eventType: "journey_deleted", details: ["journeyId": journeyID.uuidString])
            markSyncSuccess("Journey deleted")
        } catch {
            markSyncFailure("Journey delete failed", error: error)
        }
#endif
    }

    private func deleteRentalFromBackend(rentalID: UUID) async {
#if canImport(FirebaseFirestore)
        guard backendUID != nil else { return }

        let db = Firestore.firestore()
        do {
            try await db.collection("rentals").document(rentalID.uuidString).delete()

            // Snapshot is keyed by rental ID; deleting it keeps trip history + research data aligned.
            try? await db.collection("ride_snapshots").document(rentalID.uuidString).delete()

            await persistResearchEvent(eventType: "rental_deleted", details: ["rentalId": rentalID.uuidString])
            markSyncSuccess("Rental deleted")
        } catch {
            markSyncFailure("Rental delete failed", error: error)
        }
#endif
    }

    private func loadJourneysFromBackend() async {
#if canImport(FirebaseFirestore)
        guard let uid = backendUID else { return }
        let db = Firestore.firestore()

        do {
            let snapshot = try await db.collection("journeys")
                .whereField("authorId", isEqualTo: uid)
                .order(by: "updatedAt", descending: true)
                .getDocuments()
            let loaded: [Journey] = snapshot.documents.compactMap { doc in
                let data = doc.data()
                let journeyID = UUID(uuidString: data["journeyId"] as? String ?? "") ?? UUID(uuidString: doc.documentID) ?? UUID()
                guard
                    let title = data["title"] as? String,
                    let subtitle = data["subtitle"] as? String,
                    let description = data["description"] as? String,
                    let startName = data["startName"] as? String,
                    let destinationName = data["destinationName"] as? String,
                    let startLat = data["startLat"] as? Double,
                    let startLng = data["startLng"] as? Double,
                    let destinationLat = data["destinationLat"] as? Double,
                    let destinationLng = data["destinationLng"] as? Double,
                    let difficulty = data["difficulty"] as? String
                else {
                    return nil
                }

                let categoryRaw = data["category"] as? String ?? JourneyCategory.community.rawValue
                let category = JourneyCategory(rawValue: categoryRaw) ?? .community
                let imageName = data["imageName"] as? String ?? "figure.outdoor.cycle"
                let usesAssetImage = data["usesAssetImage"] as? Bool ?? false

                return Journey(
                    id: journeyID,
                    title: title,
                    subtitle: subtitle,
                    description: description,
                    startName: startName,
                    destinationName: destinationName,
                    startLatitude: startLat,
                    startLongitude: startLng,
                    destinationLatitude: destinationLat,
                    destinationLongitude: destinationLng,
                    difficulty: difficulty,
                    category: category,
                    imageName: imageName,
                    usesAssetImage: usesAssetImage
                )
            }

            var mergedByID = Dictionary(uniqueKeysWithValues: journeys.map { ($0.id, $0) })
            for journey in loaded {
                mergedByID[journey.id] = journey
            }
            journeys = Array(mergedByID.values)
            myJourneyIDs = Set(loaded.map(\.id))
            markSyncSuccess("Journeys loaded")
        } catch {
            markSyncFailure("Journey load failed", error: error)
        }
#endif
    }

    private func loadCommunityPostsFromBackend(uid _: String) async {
#if canImport(FirebaseFirestore)
        let db = Firestore.firestore()

        do {
            // No server-side ordering: prevents older docs without specific timestamp fields from disappearing.
            let snapshot = try await db.collection("posts")
                .limit(to: 500)
                .getDocuments()

            let loaded: [CommunityPost] = snapshot.documents.compactMap { doc in
                decodeCommunityPost(from: doc)
            }
            .sorted(by: { $0.createdAt > $1.createdAt })

            // Keep one local example only when backend has no posts.
            if !loaded.isEmpty {
                communityPosts = loaded
            }
            await hydrateRoutePathsForCommunityPosts(posts: loaded)
            markSyncSuccess("Posts loaded")
        } catch {
            markSyncFailure("Post load failed", error: error)
        }
#endif
    }

#if canImport(FirebaseFirestore)
    private func startCommunityPostsListener() {
        stopCommunityPostsListener()

        let db = Firestore.firestore()
        communityPostsListener = db.collection("posts")
            .limit(to: 500)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }

                Task { @MainActor in
                    if let error {
                        self.markSyncFailure("Post listener failed", error: error)
                        return
                    }

                    guard let snapshot else { return }
                    let loaded: [CommunityPost] = snapshot.documents.compactMap { doc in
                        self.decodeCommunityPost(from: doc)
                    }
                    .sorted(by: { $0.createdAt > $1.createdAt })

                    if !loaded.isEmpty {
                        self.communityPosts = loaded
                    }

                    await self.hydrateRoutePathsForCommunityPosts(posts: loaded)

                    self.markSyncSuccess("Community feed live")
                }
            }
    }

    private func stopCommunityPostsListener() {
        communityPostsListener?.remove()
        communityPostsListener = nil
    }

    private func decodeCommunityPost(from doc: QueryDocumentSnapshot) -> CommunityPost? {
        let data = doc.data()
        let postID = UUID(uuidString: data["postId"] as? String ?? "") ?? UUID(uuidString: doc.documentID) ?? UUID()

        guard
            let authorName = data["authorName"] as? String,
            let journeyTitle = data["journeyTitle"] as? String,
            let bodyText = data["bodyText"] as? String
        else {
            return nil
        }

        let authorID = data["authorId"] as? String
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
        let legacyLikes = data["likes"] as? Int ?? 0
        let likedUserIDsArray = data["likedUserIDs"] as? [String] ?? []
        let likedUserIDs = Set(likedUserIDsArray)
        let likes = likedUserIDs.isEmpty ? legacyLikes : likedUserIDs.count
        let isLikedByCurrentUser = {
            let legacyUserLike = data["isLikedByCurrentUser"] as? Bool ?? false
            guard let uid = backendUID else { return legacyUserLike }
            if likedUserIDs.isEmpty { return legacyUserLike }
            return likedUserIDs.contains(uid)
        }()
        let attachedRentalID = UUID(uuidString: data["attachedRentalId"] as? String ?? "")
        let photoURL = data["photoURL"] as? String
        let imageBase64 = data["imageBase64"] as? String
        let decodedImageData = imageBase64.flatMap { Data(base64Encoded: $0) }

        let rawComments = data["comments"] as? [[String: Any]] ?? []
        let comments: [PostComment] = rawComments.compactMap { entry in
            guard
                let author = entry["authorName"] as? String,
                let text = entry["text"] as? String
            else {
                return nil
            }

            let commentID = UUID(uuidString: entry["id"] as? String ?? "") ?? UUID()
            let commentDate = (entry["createdAt"] as? Timestamp)?.dateValue() ?? Date()
            return PostComment(id: commentID, authorName: author, text: text, createdAt: commentDate)
        }

        return CommunityPost(
            id: postID,
            authorName: authorName,
            authorID: authorID,
            journeyTitle: journeyTitle,
            bodyText: bodyText,
            createdAt: createdAt,
            attachedRentalID: attachedRentalID,
            likes: likes,
            isLikedByCurrentUser: isLikedByCurrentUser,
            likedUserIDs: likedUserIDs,
            comments: comments,
            imageData: decodedImageData,
            photoURL: photoURL
        )
    }


    private func decodeCoordinatePath(from raw: Any?) -> [CLLocationCoordinate2D] {
        guard let entries = raw as? [[String: Any]] else { return [] }
        return entries.compactMap { item in
            guard let lat = item["lat"] as? Double, let lng = item["lng"] as? Double else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
    }

    private func decodeCoordinatePath(fromDoubleDict raw: Any?) -> [CLLocationCoordinate2D] {
        guard let entries = raw as? [[String: Double]] else { return [] }
        return entries.compactMap { item in
            guard let lat = item["lat"], let lng = item["lng"] else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
    }

    private func mergeDecodedPath(_ data: [String: Any]) -> [CLLocationCoordinate2D] {
        let primary = decodeCoordinatePath(from: data["trackedPath"])
        if !primary.isEmpty { return primary }
        let fallbackA = decodeCoordinatePath(from: data["trackedPathSample"])
        if !fallbackA.isEmpty { return fallbackA }
        let fallbackB = decodeCoordinatePath(fromDoubleDict: data["trackedPath"])
        if !fallbackB.isEmpty { return fallbackB }
        return decodeCoordinatePath(fromDoubleDict: data["trackedPathSample"])
    }

    private func chunked<T>(_ array: [T], size: Int) -> [[T]] {
        guard size > 0 else { return [array] }
        var result: [[T]] = []
        var index = 0
        while index < array.count {
            let end = min(index + size, array.count)
            result.append(Array(array[index..<end]))
            index = end
        }
        return result
    }

    private func hydrateRoutePathsForCommunityPosts(posts: [CommunityPost]) async {
#if canImport(FirebaseFirestore)
        let rentalIDs = Array(Set(posts.compactMap(\.attachedRentalID)))
        guard !rentalIDs.isEmpty else { return }

        let uncached = rentalIDs.filter { routePathByRentalID[$0] == nil }
        guard !uncached.isEmpty else { return }

        let db = Firestore.firestore()
        for group in chunked(uncached, size: 10) {
            let documentIDs = group.map(\.uuidString)
            do {
                let snapshot = try await db.collection("ride_snapshots")
                    .whereField(FieldPath.documentID(), in: documentIDs)
                    .getDocuments()

                for doc in snapshot.documents {
                    guard let rentalID = UUID(uuidString: doc.documentID) else { continue }
                    let path = mergeDecodedPath(doc.data())
                    if !path.isEmpty {
                        routePathByRentalID[rentalID] = path
                    }
                }
            } catch {
                markSyncFailure("Route hydration failed", error: error)
            }
        }
#endif
    }

#endif

    private func samplePath(_ trackedPath: [CLLocationCoordinate2D], maxPoints: Int) -> [[String: Double]] {
        guard !trackedPath.isEmpty else { return [] }
        guard trackedPath.count > maxPoints else {
            return trackedPath.map { ["lat": $0.latitude, "lng": $0.longitude] }
        }

        let strideSize = max(1, trackedPath.count / maxPoints)
        var sampled: [[String: Double]] = []
        sampled.reserveCapacity(maxPoints)

        var index = 0
        while index < trackedPath.count {
            let point = trackedPath[index]
            sampled.append(["lat": point.latitude, "lng": point.longitude])
            index += strideSize
        }

        if let last = trackedPath.last {
            let lastMapped = ["lat": last.latitude, "lng": last.longitude]
            if sampled.last != lastMapped {
                sampled.append(lastMapped)
            }
        }

        return sampled
    }

    private func routeBounds(for trackedPath: [CLLocationCoordinate2D]) -> (minLat: Double?, maxLat: Double?, minLng: Double?, maxLng: Double?) {
        guard let first = trackedPath.first else {
            return (nil, nil, nil, nil)
        }

        var minLat = first.latitude
        var maxLat = first.latitude
        var minLng = first.longitude
        var maxLng = first.longitude

        for point in trackedPath.dropFirst() {
            minLat = min(minLat, point.latitude)
            maxLat = max(maxLat, point.latitude)
            minLng = min(minLng, point.longitude)
            maxLng = max(maxLng, point.longitude)
        }

        return (minLat, maxLat, minLng, maxLng)
    }

    private func compressedJPEGData(from input: Data) -> Data? {
#if canImport(UIKit)
        guard let image = UIImage(data: input) else { return nil }
        return image.jpegData(compressionQuality: 0.35)
#elseif canImport(AppKit)
        guard let image = NSImage(data: input),
              let tiffData = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.35])
#else
        return nil
#endif
    }

    private func markSyncSuccess(_ status: String) {
        lastSyncStatus = status
        lastSyncAt = Date()
        lastSyncError = nil
    }

    private func markSyncFailure(_ status: String, error: Error) {
        lastSyncStatus = status
        lastSyncAt = Date()
        lastSyncError = error.localizedDescription
        print("\(status): \(error.localizedDescription)")
    }

#if canImport(FirebaseStorage)
    private func uploadProfileImageData(_ imageData: Data, uid: String) async -> String? {
        let ref = Storage.storage().reference().child("profile_photos/\(uid).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        do {
            _ = try await ref.putDataAsync(imageData, metadata: metadata)
            let url = try await ref.downloadURL()
            return url.absoluteString
        } catch {
            markSyncFailure("Profile image upload failed", error: error)
            return nil
        }
    }

    private func uploadPostImageData(_ imageData: Data, postID: UUID) async -> String? {
        let ref = Storage.storage().reference().child("posts/\(postID.uuidString).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        do {
            _ = try await ref.putDataAsync(imageData, metadata: metadata)
            let url = try await ref.downloadURL()
            return url.absoluteString
        } catch {
            markSyncFailure("Post image upload failed", error: error)
            return nil
        }
    }
#endif
}
