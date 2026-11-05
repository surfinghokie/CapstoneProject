import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif

struct ActivityView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var rideTrackingManager: RideTrackingManager
    @State private var selectedSection = 0
    @State private var showingComposer = false
    @State private var commentDraftByPostID: [UUID: String] = [:]
    @State private var pendingPostDelete: CommunityPost?

    var body: some View {
        VStack(spacing: 10) {
            Picker("Activity", selection: $selectedSection) {
                Text("Community").tag(0)
                Text("My Trips").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if selectedSection == 0 {
                communitySection
            } else {
                MyRentalsView()
                    .environmentObject(viewModel)
                    .environmentObject(rideTrackingManager)
            }
        }
        .navigationTitle("Activity")
        .toolbar {
            if selectedSection == 0 {
                Button {
                    showingComposer = true
                } label: {
                    Label("Create Post", systemImage: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $showingComposer) {
            NavigationStack {
                PostComposerView { journeyTitle, body, imageData in
                    viewModel.createPost(journeyTitle: journeyTitle, bodyText: body, imageData: imageData)
                }
            }
        }
        .alert(
            "Delete Post?",
            isPresented: Binding(
                get: { pendingPostDelete != nil },
                set: { if !$0 { pendingPostDelete = nil } }
            ),
            presenting: pendingPostDelete
        ) { post in
            Button("Delete", role: .destructive) {
                viewModel.deletePost(postID: post.id)
                pendingPostDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingPostDelete = nil
            }
        } message: { _ in
            Text("This post and its comments will be removed.")
        }
    }

    private var communitySection: some View {
        List {
            Section {
                Text("Share your routes, journey photos, and ride activity with the HokieBike community.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(viewModel.communityPosts) { post in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(post.authorName)
                            .font(.headline)
                        Spacer()
                        if post.authorName == viewModel.currentUser.name {
                            Button(role: .destructive) {
                                pendingPostDelete = post
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        Text(post.createdAt, style: .relative)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(post.journeyTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(post.bodyText)
                        .font(.subheadline)

                    if let imageData = post.imageData {
                        CommunityPostImage(data: imageData)
                    } else if let photoURL = post.photoURL,
                              let url = URL(string: photoURL),
                              !photoURL.isEmpty {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 180)
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                    .cornerRadius(10)
                            case .failure:
                                EmptyView()
                            default:
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }

                    HStack(spacing: 16) {
                        Button {
                            viewModel.toggleLike(postID: post.id)
                        } label: {
                            Label("\(post.likes)", systemImage: post.isLikedByCurrentUser ? "heart.fill" : "heart")
                                .foregroundColor(post.isLikedByCurrentUser ? .red : .primary)
                        }

                        Text("\(post.comments.count) comments")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if !post.comments.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(post.comments.suffix(2)) { comment in
                                Text("\(comment.authorName): \(comment.text)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    HStack {
                        TextField("Add a comment", text: Binding(
                            get: { commentDraftByPostID[post.id, default: ""] },
                            set: { commentDraftByPostID[post.id] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)

                        Button("Send") {
                            let text = commentDraftByPostID[post.id, default: ""]
                            viewModel.addComment(postID: post.id, text: text)
                            commentDraftByPostID[post.id] = ""
                        }
                    }
                }
                .padding(.vertical, 6)
                .contextMenu {
                    if post.authorName == viewModel.currentUser.name {
                        Button(role: .destructive) {
                            pendingPostDelete = post
                        } label: {
                            Label("Delete Post", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

}

private struct CommunityPostImage: View {
    let data: Data

    var body: some View {
        #if canImport(UIKit)
        if let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipped()
                .cornerRadius(10)
        }
        #elseif canImport(AppKit)
        if let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipped()
                .cornerRadius(10)
        }
        #else
        EmptyView()
        #endif
    }
}

private struct PostComposerView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var journeyTitle = ""
    @State private var bodyText = ""
    @State private var selectedImageData: Data?
#if canImport(PhotosUI)
    @State private var selectedPickerItem: PhotosPickerItem?
#endif

    let onShare: (_ journeyTitle: String, _ bodyText: String, _ imageData: Data?) -> Void

    var body: some View {
        Form {
            Section("Journey") {
                TextField("Journey title", text: $journeyTitle)
                TextField("How was your journey?", text: $bodyText, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section("Photo") {
#if canImport(PhotosUI)
                PhotosPicker(selection: $selectedPickerItem, matching: .images) {
                    Label("Choose Photo", systemImage: "photo")
                }
                .onChange(of: selectedPickerItem) { _, newItem in
                    Task {
                        selectedImageData = try? await newItem?.loadTransferable(type: Data.self)
                    }
                }
#else
                Text("Photo picker unavailable on this platform.")
                    .font(.caption)
                    .foregroundColor(.secondary)
#endif

                if let selectedImageData {
                    CommunityPostImage(data: selectedImageData)
                }
            }
        }
        .navigationTitle("Share Journey")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Share") {
                    onShare(journeyTitle.isEmpty ? "Recent Ride" : journeyTitle, bodyText, selectedImageData)
                    dismiss()
                }
                .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ActivityView()
            .environmentObject(AppViewModel())
            .environmentObject(RideTrackingManager())
    }
}
