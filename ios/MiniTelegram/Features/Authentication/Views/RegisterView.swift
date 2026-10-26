import SwiftUI
import PhotosUI

public struct RegisterView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AuthViewModel

    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showingAvatarPresets = false

    public init(viewModel: AuthViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Header
                VStack(spacing: AppSpacing.xs) {
                    Text("Create Account")
                        .font(AppTypography.largeTitle)
                        .foregroundColor(AppColors.textPrimary)

                    Text("Join Our Chat to message, call, and connect with friends.")
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.lg)
                }
                .padding(.top, AppSpacing.md)

                // Profile Photo Section
                VStack(spacing: AppSpacing.xs) {
                    ZStack(alignment: .bottomTrailing) {
                        AvatarView(
                            name: viewModel.displayName.isEmpty ? "Our Chat" : viewModel.displayName,
                            avatarUrl: viewModel.avatarBase64,
                            size: 90
                        )

                        PhotosPicker(
                            selection: $selectedPhotoItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                                .background(AppColors.accent)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(AppColors.background, lineWidth: 2))
                        }
                        .accessibilityLabel("Upload a profile photo")
                    }

                    HStack(spacing: AppSpacing.md) {
                        PhotosPicker(
                            selection: $selectedPhotoItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Text("Upload Photo")
                                .font(AppTypography.footnote.weight(.semibold))
                                .foregroundColor(AppColors.accent)
                        }

                        Text("•")
                            .foregroundColor(AppColors.textTertiary)

                        Button(action: {
                            showingAvatarPresets.toggle()
                        }) {
                            Text("Choose Illustrated Avatar")
                                .font(AppTypography.footnote.weight(.semibold))
                                .foregroundColor(AppColors.accent)
                        }
                        .accessibilityHint("Choose a 2D illustrated profile portrait")
                    }

                    if showingAvatarPresets {
                        IllustratedAvatarPicker(selection: $viewModel.avatarBase64)
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.top, AppSpacing.xs)
                    }
                }
                .padding(.vertical, AppSpacing.xs)

                // Error Banner
                if let errorMessage = viewModel.errorMessage {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(AppColors.statusError)
                        Text(errorMessage)
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.statusError)
                    }
                    .padding(AppSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.statusError.opacity(0.1))
                    .cornerRadius(AppCornerRadius.sm)
                    .padding(.horizontal, AppSpacing.lg)
                }

                // Progress Indicator
                if let progress = viewModel.keyGenerationProgress {
                    HStack(spacing: AppSpacing.xs) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(progress)
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.accent)
                    }
                    .padding(.horizontal, AppSpacing.lg)
                }

                // Form Fields
                VStack(spacing: AppSpacing.md) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Full Name")
                            .font(AppTypography.footnote.weight(.semibold))
                            .foregroundColor(AppColors.textSecondary)

                        CustomTextField(
                            placeholder: "e.g. John Doe",
                            text: $viewModel.displayName,
                            autocapitalization: .words
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Username")
                            .font(AppTypography.footnote.weight(.semibold))
                            .foregroundColor(AppColors.textSecondary)

                        CustomTextField(
                            placeholder: "e.g. johndoe",
                            text: $viewModel.username,
                            autocapitalization: .never
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Phone Number")
                            .font(AppTypography.footnote.weight(.semibold))
                            .foregroundColor(AppColors.textSecondary)

                        CustomTextField(
                            placeholder: "+1 234 567 8900",
                            text: $viewModel.phoneNumber,
                            keyboardType: .phonePad,
                            autocapitalization: .never
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Password")
                            .font(AppTypography.footnote.weight(.semibold))
                            .foregroundColor(AppColors.textSecondary)

                        CustomTextField(
                            placeholder: "At least 6 characters",
                            text: $viewModel.password,
                            isSecure: true
                        )
                    }

                    PrimaryButton(
                        title: "Create Account",
                        icon: "checkmark.shield.fill",
                        isLoading: viewModel.isLoading
                    ) {
                        Task {
                            _ = await viewModel.registerNormal(appState: appState)
                        }
                    }
                    .padding(.top, AppSpacing.xs)
                }
                .padding(.horizontal, AppSpacing.lg)

                // Already have account
                Button(action: {
                    dismiss()
                }) {
                    HStack(spacing: 4) {
                        Text("Already have an account?")
                            .foregroundColor(AppColors.textSecondary)
                        Text("Log In")
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.accent)
                    }
                    .font(AppTypography.subheadline)
                }
                .padding(.top, AppSpacing.xs)
            }
            .padding(.bottom, AppSpacing.xxl)
        }
        .background(AppColors.background)
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if viewModel.avatarBase64 == nil {
                viewModel.avatarBase64 = IllustratedAvatarPreset.sunny.storageValue
            }
        }
        .onChange(of: selectedPhotoItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    if let image = UIImage(data: data) {
                        let resized = resizeImage(image: image, targetSize: CGSize(width: 256, height: 256))
                        if let jpegData = resized.jpegData(compressionQuality: 0.7) {
                            viewModel.avatarBase64 = jpegData.base64EncodedString()
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
