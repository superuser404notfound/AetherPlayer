import AetherEngine

struct AudioMenuRow: Identifiable, Equatable {
    let id: Int            // engine track index
    var engineIndex: Int { id }
    let label: String
    let isSelected: Bool
}

struct SubtitleMenuRow: Identifiable, Equatable {
    enum Kind: Equatable { case off, track(engineIndex: Int) }
    let id: Int            // -1 for Off, else engine index
    let kind: Kind
    let label: String
    let isSelected: Bool
}

private func channelLabel(_ channels: Int) -> String? {
    switch channels {
    case 0: return nil
    case 1: return String(localized: "Mono")
    case 2: return String(localized: "Stereo")
    case 6: return "5.1"
    case 8: return "7.1"
    default: return "\(channels)ch"
    }
}

private func audioLabel(_ t: TrackInfo) -> String {
    var parts = [t.name.isEmpty ? String(localized: "Track \(t.id)") : t.name]
    if let lang = t.language, !lang.isEmpty { parts.append(lang.uppercased()) }
    if t.isAtmos { parts.append("Atmos") }
    else if let ch = channelLabel(t.channels) { parts.append(ch) }
    return parts.joined(separator: " \u{00B7} ")
}

private func subtitleLabel(_ t: TrackInfo) -> String {
    var parts = [t.name.isEmpty ? String(localized: "Track \(t.id)") : t.name]
    if let lang = t.language, !lang.isEmpty { parts.append(lang.uppercased()) }
    return parts.joined(separator: " \u{00B7} ")
}

func audioMenuRows(_ tracks: [TrackInfo], activeIndex: Int?) -> [AudioMenuRow] {
    tracks.map { t in
        AudioMenuRow(id: t.id, label: audioLabel(t), isSelected: t.id == activeIndex)
    }
}

func subtitleMenuRows(_ tracks: [TrackInfo], selectedEngineIndex: Int?, isActive: Bool) -> [SubtitleMenuRow] {
    var rows: [SubtitleMenuRow] = [
        SubtitleMenuRow(id: -1, kind: .off, label: String(localized: "Off"), isSelected: !isActive)
    ]
    rows += tracks.map { t in
        SubtitleMenuRow(
            id: t.id,
            kind: .track(engineIndex: t.id),
            label: subtitleLabel(t),
            isSelected: isActive && t.id == selectedEngineIndex
        )
    }
    return rows
}

// MARK: - Disc titles + chapters (#67)

struct TitleMenuRow: Identifiable, Equatable {
    let id: Int            // engine title id
    let label: String
    let isSelected: Bool
}

struct ChapterMenuRow: Identifiable, Equatable {
    let id: Int            // engine chapter id
    let label: String
}

func discTimecode(_ seconds: Double) -> String {
    let t = Int(seconds.rounded())
    return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
}

private func titleLabel(_ t: TitleInfo) -> String {
    var parts = [t.name.isEmpty ? String(localized: "Title \(t.id + 1)") : t.name]
    if t.durationSeconds > 0 { parts.append(discTimecode(t.durationSeconds)) }
    if t.chapterCount > 0 { parts.append(String(localized: "\(t.chapterCount) ch", comment: "Chapter count of a disc title")) }
    return parts.joined(separator: " \u{00B7} ")
}

func titleMenuRows(_ titles: [TitleInfo], selectedID: Int?) -> [TitleMenuRow] {
    titles.map { t in
        TitleMenuRow(id: t.id, label: titleLabel(t), isSelected: t.id == selectedID)
    }
}

func chapterMenuRows(_ chapters: [ChapterInfo]) -> [ChapterMenuRow] {
    chapters.map { c in
        let name = c.name.isEmpty ? String(localized: "Chapter \(c.id + 1)") : c.name
        return ChapterMenuRow(id: c.id, label: "\(name) \u{00B7} \(discTimecode(c.startSeconds))")
    }
}
