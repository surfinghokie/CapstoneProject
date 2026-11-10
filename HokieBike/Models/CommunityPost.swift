import Foundation

struct PostComment: Identifiable, Equatable {
    let id: UUID
    let authorName: String
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), authorName: String, text: String, createdAt: Date = Date()) {
        self.id = id
        self.authorName = authorName
        self.text = text
        self.createdAt = createdAt
    }
}

struct CommunityPost: Identifiable, Equatable {
    let id: UUID
    let authorName: String
    let authorID: String?
    let journeyTitle: String
    let bodyText: String
    let createdAt: Date
    let attachedRentalID: UUID?
    var likes: Int
    var isLikedByCurrentUser: Bool
    var likedUserIDs: Set<String>
    var comments: [PostComment]
    var imageData: Data?
    var photoURL: String?

    init(
        id: UUID = UUID(),
        authorName: String,
        authorID: String? = nil,
        journeyTitle: String,
        bodyText: String,
        createdAt: Date = Date(),
        attachedRentalID: UUID? = nil,
        likes: Int = 0,
        isLikedByCurrentUser: Bool = false,
        likedUserIDs: Set<String> = [],
        comments: [PostComment] = [],
        imageData: Data? = nil,
        photoURL: String? = nil
    ) {
        self.id = id
        self.authorName = authorName
        self.authorID = authorID
        self.journeyTitle = journeyTitle
        self.bodyText = bodyText
        self.createdAt = createdAt
        self.attachedRentalID = attachedRentalID
        self.likes = likes
        self.isLikedByCurrentUser = isLikedByCurrentUser
        self.likedUserIDs = likedUserIDs
        self.comments = comments
        self.imageData = imageData
        self.photoURL = photoURL
    }
}
