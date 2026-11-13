import Foundation

/// Matches the broadcaster's full network name while allowing common IPTV
/// region and stream-quality labels. Other networks in the same family are
/// deliberately excluded (ESPN is not ESPN 2, ESPN+, or ESPN Deportes).
nonisolated enum SportsZoneBroadcasterMatcher {
    enum Match: Int, Equatable {
        case exact = 100
        case feedVariant = 75

        var score: Int { rawValue }
    }

    // Only transport/quality labels belong here. Network names and service
    // labels such as News, Deportes, Plus and 2 must never be stripped.
    private static let feedLabels: Set<String> = [
        "sd", "hd", "fhd", "fullhd", "uhd", "4k", "8k", "hdr", "hdr10",
        "480p", "576p", "720p", "1080p", "2160p", "720", "1080", "2160",
        "avc", "hevc", "h264", "h265", "50fps", "60fps", "backup", "bkp", "alt"
    ]
    private static let regionLabels: Set<String> = [
        "us", "usa", "uk", "gb", "ca", "au", "de", "fr", "it", "es", "pt",
        "br", "nl", "mx", "eu", "latam"
    ]

    static func match(broadcaster: String, channelName: String) -> Match? {
        let expected = networkTokens(broadcaster)
        guard !expected.isEmpty else { return nil }
        var candidate = networkTokens(channelName)
        if candidate == expected { return .exact }

        // Region labels may be before the network. Quality labels and region
        // tags may follow it in any order, as with "US: ESPN FHD [1080p]".
        while let first = candidate.first, regionLabels.contains(first) {
            candidate.removeFirst()
        }
        while let last = candidate.last,
              feedLabels.contains(last) || regionLabels.contains(last) {
            candidate.removeLast()
        }
        return candidate == expected ? .feedVariant : nil
    }

    private static func networkTokens(_ raw: String) -> [String] {
        // The normal text fold removes punctuation. Preserve a plus suffix,
        // because ESPN+ and ESPN are different networks.
        SportsMatcher.normalize(raw.replacingOccurrences(of: "+", with: " plus "))
            .split(separator: " ")
            .flatMap { expandNetworkNumber(String($0)) }
    }

    private static func expandNetworkNumber(_ word: String) -> [String] {
        // ESPN2 == ESPN 2 and BBC1 == BBC 1; both remain different from ESPN/BBC.
        guard let firstDigit = word.firstIndex(where: { $0.isNumber }) else { return [word] }
        let prefix = word[..<firstDigit]
        let number = word[firstDigit...]
        guard prefix.count >= 2, number.count <= 2,
              prefix.allSatisfy({ $0.isLetter }), number.allSatisfy({ $0.isNumber }) else { return [word] }
        return [String(prefix), String(number)]
    }
}
