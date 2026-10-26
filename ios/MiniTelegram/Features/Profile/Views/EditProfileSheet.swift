import SwiftUI
import PhotosUI

public struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: ProfileViewModel

    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedCoverPhotoItem: PhotosPickerItem? = nil
    @State private var showingAvatarPicker = false

    public init(viewModel: ProfileViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                // Profile Cover Banner Section
                Section(header: Text("Profile Cover Banner")) {
                    VStack(spacing: AppSpacing.sm) {
                        ProfileCoverBannerView(coverUrl: viewModel.editCoverUrl, height: 110)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(ProfileCoverPreset.allCases) { preset in
                                    let isSelected = viewModel.editCoverUrl == preset.rawValue
                                    Button {
                                        viewModel.editCoverUrl = preset.rawValue
                                    } label: {
                                        HStack(spacing: 5) {
                                            Circle()
                                                .fill(preset.gradientColors.first ?? .gray)
                                                .frame(width: 12, height: 12)
                                            Text(preset.displayName)
                                                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? Color(red: 0.83, green: 0.69, blue: 0.35).opacity(0.18) : AppColors.secondaryBackground)
                                        .overlay(
                                            Capsule().stroke(isSelected ? Color(red: 0.83, green: 0.69, blue: 0.35) : Color.clear, lineWidth: 1)
                                        )
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }

                        PhotosPicker(
                            selection: $selectedCoverPhotoItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            HStack(spacing: 5) {
                                Image(systemName: "camera.fill")
                                Text("Upload Custom Cover Photo")
                            }
                            .font(AppTypography.footnote.weight(.semibold))
                            .foregroundColor(AppColors.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(AppColors.secondaryBackground, in: RoundedRectangle(cornerRadius: AppCornerRadius.sm))
                        }
                    }
                    .padding(.vertical, AppSpacing.xs)
                }

                // Avatar & Border Section
                Section(header: Text("Profile Avatar")) {
                    HStack {
                        Spacer()
                        VStack(spacing: AppSpacing.sm) {
                            AvatarView(
                                name: viewModel.editDisplayName.isEmpty ? "User" : viewModel.editDisplayName,
                                avatarUrl: viewModel.editAvatarBase64,
                                size: 84,
                                borderTemplate: ProfileBorderTemplate.from(raw: viewModel.editBorderTemplate)
                            )

                            HStack(spacing: AppSpacing.md) {
                                PhotosPicker(
                                    selection: $selectedPhotoItem,
                                    matching: .images,
                                    photoLibrary: .shared()
                                ) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "photo")
                                        Text("Choose Photo")
                                    }
                                    .font(AppTypography.footnote.weight(.semibold))
                                    .foregroundColor(AppColors.accent)
                                }

                                Button(action: {
                                    showingAvatarPicker.toggle()
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "person.crop.circle")
                                        Text("Illustrated Avatar")
                                    }
                                    .font(AppTypography.footnote.weight(.semibold))
                                    .foregroundColor(AppColors.accent)
                                }
                                .accessibilityHint("Choose an illustrated profile portrait")
                            }

                            if showingAvatarPicker {
                                IllustratedAvatarPicker(selection: $viewModel.editAvatarBase64)
                                    .padding(.top, AppSpacing.xs)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, AppSpacing.xs)
                }

                // Profile Border Template Section (Modern Clean & Luxury)
                Section(header: Text("Profile Border Template (Modern Clean & Luxury)")) {
                    ProfileBorderTemplatePicker(
                        selection: $viewModel.editBorderTemplate,
                        avatarName: viewModel.editDisplayName.isEmpty ? "User" : viewModel.editDisplayName,
                        avatarUrl: viewModel.editAvatarBase64
                    )
                    .padding(.vertical, AppSpacing.xs)
                }


                // Account Information
                Section(header: Text("Account Details")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Display Name")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textSecondary)
                        TextField("Your full name", text: $viewModel.editDisplayName)
                            .font(AppTypography.body)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Username")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textSecondary)
                        TextField("username", text: $viewModel.editUsername)
                            .font(AppTypography.body)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Phone Number")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textSecondary)
                        TextField("+1 234 567 890", text: $viewModel.editPhoneNumber)
                            .font(AppTypography.body)
                            .keyboardType(.phonePad)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bio")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textSecondary)
                        TextField("Tell friends about yourself...", text: $viewModel.editBio, axis: .vertical)
                            .lineLimit(3...5)
                            .font(AppTypography.body)
                    }
                }

                // App Owner Exclusive: Custom Name Color Selection
                if appState.currentUser?.isAppOwner == true {
                    Section {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            // Live Preview
                            HStack {
                                Text("Preview:")
                                    .font(AppTypography.subheadline)
                                    .foregroundColor(AppColors.textSecondary)

                                AccountDisplayNameView(
                                    name: viewModel.editDisplayName.isEmpty ? "Owner" : viewModel.editDisplayName,
                                    isDeveloper: true,
                                    isOwner: true,
                                    nameColorHex: viewModel.editNameColor.isEmpty ? NameColorTheme.imperialRed.hex : viewModel.editNameColor,
                                    font: AppTypography.headline.weight(.bold)
                                )
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(AppColors.secondaryBackground, in: RoundedRectangle(cornerRadius: AppCornerRadius.sm))

                            // Color Chips Grid
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(NameColorTheme.allPresets) { preset in
                                        let isSelected = viewModel.editNameColor.caseInsensitiveCompare(preset.hex) == .orderedSame ||
                                            (viewModel.editNameColor.isEmpty && preset.id == NameColorTheme.imperialRed.id)
                                        Button {
                                            viewModel.editNameColor = preset.hex
                                        } label: {
                                            VStack(spacing: 5) {
                                                ZStack {
                                                    Circle()
                                                        .fill(preset.color)
                                                        .frame(width: 32, height: 32)
                                                        .shadow(color: preset.color.opacity(0.35), radius: 4)

                                                    if isSelected {
                                                        Circle()
                                                            .stroke(Color.white, lineWidth: 2.5)
                                                            .frame(width: 36, height: 36)
                                                        Image(systemName: "checkmark")
                                                            .font(.system(size: 13, weight: .bold))
                                                            .foregroundColor(.white)
                                                    }
                                                }

                                                Text(preset.name)
                                                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                                    .foregroundColor(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
                                                    .lineLimit(1)
                                            }
                                            .frame(width: 68)
                                            .padding(.vertical, 6)
                                            .background(isSelected ? preset.color.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            }

                            // Custom Hex Field
                            HStack(spacing: 8) {
                                Text("Custom HEX")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.textSecondary)

                                TextField("#FF3B30", text: $viewModel.editNameColor)
                                    .font(AppTypography.caption.monospaced())
                                    .autocapitalization(.allCharacters)
                                    .disableAutocorrection(true)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(AppColors.secondaryBackground, in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        HStack(spacing: 5) {
                            Image(systemName: "crown.fill")
                                .foregroundColor(Color(red: 0.96, green: 0.82, blue: 0.25))
                            Text("Owner Display Name Color")
                        }
                    } footer: {
                        Text("As app owner, your display name defaults to Imperial Red and can be changed to any luxury hue visible to everyone in the app.")
                    }
                }

                Section {
                    TextField("e.g. iOS developer building thoughtful apps", text: $viewModel.editDeveloperHeadline, axis: .vertical)
                        .lineLimit(2...3)
                    TextField("Swift, SwiftUI, TypeScript", text: $viewModel.editSkills)
                        .textInputAutocapitalization(.words)
                    TextField("Currently building", text: $viewModel.editCurrentlyBuilding)
                    TextField("City or region", text: $viewModel.editLocation)

                    Picker("Availability", selection: $viewModel.editWorkAvailability) {
                        Text("Not listed").tag("not_listed")
                        Text("Open to opportunities").tag("open_to_opportunities")
                        Text("Available for work").tag("available_for_work")
                    }
                } header: {
                    Text("Developer Profile")
                } footer: {
                    Text("Developer details and links are visible to everyone who can view your profile.")
                }

                Section {
                    TextField("Portfolio website", text: $viewModel.editWebsiteURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("GitHub profile", text: $viewModel.editGitHubURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("LinkedIn profile", text: $viewModel.editLinkedInURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Instagram profile", text: $viewModel.editInstagramURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("X profile", text: $viewModel.editXURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Links")
                }

                Section {
                    ForEach($viewModel.editProjects) { $project in
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            TextField("Project name", text: $project.title)
                                .font(AppTypography.headline)
                            TextField("What does it do?", text: $project.summary, axis: .vertical)
                                .lineLimit(2...4)
                            TextField("Tech tags, separated by commas", text: $project.technologiesText)
                            TextField("Repository URL", text: $project.repositoryURL)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            TextField("Live website URL", text: $project.liveURL)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Toggle("Pin to profile", isOn: $project.isPinned)
                            Button("Remove Project", role: .destructive) {
                                viewModel.editProjects.removeAll { $0.id == project.id }
                            }
                            .font(AppTypography.footnote)
                        }
                        .padding(.vertical, AppSpacing.xs)
                    }

                    Button {
                        viewModel.editProjects.append(DeveloperProject())
                    } label: {
                        Label("Add project", systemImage: "plus")
                    }
                } header: {
                    Text("Projects")
                } footer: {
                    Text("Pinned projects appear near the top of your public profile.")
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.statusError)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let success = await viewModel.saveProfile(appState: appState)
                            if success {
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.isUpdatingProfile)
                }
            }
            .onChange(of: selectedPhotoItem) { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        if let image = UIImage(data: data) {
                            // Resize to standard avatar size (256x256 max)
                            let resized = resizeImage(image: image, targetSize: CGSize(width: 256, height: 256))
                            if let jpegData = resized.jpegData(compressionQuality: 0.7) {
                                viewModel.editAvatarBase64 = jpegData.base64EncodedString()
                            }
                        }
                    }
                }
            }
            .onChange(of: selectedCoverPhotoItem) { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        if let image = UIImage(data: data) {
                            // Resize to cover size (800x320 max)
                            let resized = resizeImage(image: image, targetSize: CGSize(width: 800, height: 320))
                            if let jpegData = resized.jpegData(compressionQuality: 0.75) {
                                viewModel.editCoverUrl = "data:image/jpeg;base64," + jpegData.base64EncodedString()
                            }
                        }
                    }
                }
            }
        }
    }


    private func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        let newSize = widthRatio > heightRatio ?
            CGSize(width: size.width * heightRatio, height: size.height * heightRatio) :
            CGSize(width: size.width * widthRatio,  height: size.height * widthRatio)
        let rect = CGRect(origin: .zero, size: newSize)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage ?? image
    }
}
