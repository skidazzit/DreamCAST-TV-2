#if os(iOS)
import SwiftUI

/// Portrait-first featured banner based on the DreamCAST tvOS hero design.
/// The caller supplies live catalog data; no titles or artwork are hardcoded.
struct DreamCASTMobileFeaturedHero: View {
    let title: String
    let badge: String
    let artworkURL: URL?
    let fallbackURL: URL?
    let genre: String?
    let releaseDate: String?
    let contentRating: String?
    let summary: String?
    let isFavorite: Bool
    let primaryTitle: String
    let onPrimary: () -> Void
    let onInfo: () -> Void
    let onFavorite: () -> Void

    private var metadata: [String] {
        var labels: [String] = []
        if let releaseDate, !releaseDate.isEmpty {
            labels.append(String(releaseDate.prefix(4)))
        }
        if let contentRating, !contentRating.isEmpty {
            labels.append(contentRating)
        }
        if let genre, !genre.isEmpty {
            labels.append(String(genre.prefix(38)))
        }
        return labels
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            artwork
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.12), location: 0),
                    .init(color: .black.opacity(0.38), location: 0.32),
                    .init(color: DreamCASTMobileTheme.midnight.opacity(0.92), location: 0.77),
                    .init(color: DreamCASTMobileTheme.midnight, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            content
                .padding(17)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(DreamCASTMobileTheme.iceBlue.opacity(0.35), lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }

    private var artwork: some View {
        GeometryReader { geometry in
            AsyncImage(url: artworkURL ?? fallbackURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                case .empty:
                    placeholder
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    DreamCASTMobileTheme.electricBlue.opacity(0.5),
                    DreamCASTMobileTheme.midnight
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 66, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(badge.uppercased())
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(DreamCASTMobileTheme.electricBlue.opacity(0.8), in: Capsule())
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: 27, weight: .heavy, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.76)
                .shadow(color: .black.opacity(0.55), radius: 4)
            if !metadata.isEmpty {
                Text(metadata.joined(separator: "  •  "))
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .foregroundStyle(.white.opacity(0.86))
            }
            if let summary, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .lineLimit(3)
                    .foregroundStyle(.white.opacity(0.88))
            }
            HStack(spacing: 9) {
                Button(action: onPrimary) {
                    Label(primaryTitle, systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)

                Button(action: onInfo) {
                    Label("Info", systemImage: "info.circle")
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button(action: onFavorite) {
                    Image(systemName: isFavorite ? "checkmark.bookmark.fill" : "bookmark")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
    }
}
#endif
