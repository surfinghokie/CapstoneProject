import Foundation

struct User: Identifiable {
    let id: UUID
    var name: String
    var isVTStudent: Bool
    var rentalsCount: Int
    var bikesListed: Int
    var profilePhotoURL: String?
    var pilotID: String?

    init(
        id: UUID = UUID(),
        name: String,
        isVTStudent: Bool = true,
        rentalsCount: Int = 0,
        bikesListed: Int = 0,
        profilePhotoURL: String? = nil,
        pilotID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isVTStudent = isVTStudent
        self.rentalsCount = rentalsCount
        self.bikesListed = bikesListed
        self.profilePhotoURL = profilePhotoURL
        self.pilotID = pilotID
    }
}
