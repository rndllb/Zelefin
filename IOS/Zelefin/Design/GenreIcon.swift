import SwiftUI

/// Solid genre mark, in the style of the genre icon sheet.
struct GenreIcon: View {
    let title: String
    var side: CGFloat
    var tint: Color = .white

    var body: some View {
        let kind = GenreIconKind.matching(title)
        Group {
            if let asset = kind.assetName {
                Image(asset)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
            } else {
                GenreIconShape(kind: kind)
                    .fill(tint, style: FillStyle(eoFill: true))
            }
        }
        .frame(width: side, height: side)
        .foregroundStyle(tint)
        .accessibilityHidden(true)
    }
}

private enum GenreIconKind {
    case action
    case adventure
    case animation
    case anime
    case comedy
    case crime
    case documentary
    case drama
    case family
    case fantasy
    case food
    case gameShow
    case historical
    case holiday
    case horror
    case music
    case mystery
    case nature
    case news
    case reality
    case romance
    case scienceFiction
    case sciFiFantasy
    case sport
    case superhero
    case supernatural
    case suspense
    case thriller
    case war
    case western
    case children
    case biography
    case miniSeries
    case soap
    case generic

    static func matching(_ title: String) -> GenreIconKind {
        let key = title.lowercased()
        let pairs: [(String, GenreIconKind)] = [
            ("sci-fi & fantasy", .sciFiFantasy),
            ("sci-fi and fantasy", .sciFiFantasy),
            ("scifi & fantasy", .sciFiFantasy),
            ("scifi and fantasy", .sciFiFantasy),
            ("science fiction & fantasy", .sciFiFantasy),
            ("science fiction and fantasy", .sciFiFantasy),
            ("science fiction", .scienceFiction),
            ("sci-fi", .scienceFiction),
            ("scifi", .scienceFiction),
            ("historical", .historical),
            ("history", .historical),
            ("young adult", .drama),
            ("superhero", .superhero),
            ("supernatural", .supernatural),
            ("suspense", .suspense),
            ("animation", .animation),
            ("anime", .anime),
            ("adventure", .adventure),
            ("action", .action),
            ("biography", .biography),
            ("children", .children),
            ("kids", .children),
            ("kid", .children),
            ("comedy", .comedy),
            ("crime", .crime),
            ("documentary", .documentary),
            ("drama", .drama),
            ("family", .family),
            ("fantasy", .fantasy),
            ("game-show", .gameShow),
            ("game show", .gameShow),
            ("food", .food),
            ("holiday", .holiday),
            ("horror", .horror),
            ("musical", .music),
            ("music", .music),
            ("mini-series", .miniSeries),
            ("mini series", .miniSeries),
            ("miniseries", .miniSeries),
            ("mystery", .mystery),
            ("nature", .nature),
            ("news", .news),
            ("reality", .reality),
            ("romance", .romance),
            ("soap", .soap),
            ("sport", .sport),
            ("thriller", .thriller),
            ("western", .western),
            ("war", .war)
        ]
        return pairs.first { key.contains($0.0) }?.1 ?? .generic
    }

    var assetName: String? {
        switch self {
        case .romance: "GenreLovely"
        case .action: "GenrePartyPopper"
        case .adventure: "GenreZipline"
        case .documentary: "GenreDocumentText"
        case .family: "GenrePeople"
        case .fantasy: "GenreMagic"
        case .food: "GenreServingDome"
        case .gameShow: "GenreGameboy"
        case .horror: "GenreGhost"
        case .reality: "GenreVideo"
        case .music: "GenreMusicSquare"
        case .scienceFiction: "GenreTelescope"
        case .sciFiFantasy: "GenreMoon"
        case .historical: "GenreEdit"
        case .crime: "GenreCrime"
        case .comedy: "GenreComedy"
        case .anime: "GenreAnime"
        case .animation: "GenreAnimation"
        case .children: "GenreKids"
        case .mystery: "GenreMystery"
        case .miniSeries: "GenreMiniSeries"
        case .drama: "GenreDrama"
        case .soap: "GenreSoap"
        default: nil
        }
    }
}

private struct GenreIconShape: Shape {
    var kind: GenreIconKind

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        return glyph.applying(CGAffineTransform(scaleX: scale, y: scale))
    }

    private var glyph: Path {
        var path = Path()
        switch kind {
        case .action:
            path.addRoundedRect(in: CGRect(x: 1.5, y: 8.5, width: 13, height: 5.2), cornerSize: CGSize(width: 1.2, height: 1.2))
            path.addRoundedRect(in: CGRect(x: 14.4, y: 9.8, width: 8, height: 2.2), cornerSize: CGSize(width: 0.6, height: 0.6))
            path.addRoundedRect(in: CGRect(x: 4.2, y: 13.2, width: 4.2, height: 7), cornerSize: CGSize(width: 1, height: 1))
        case .adventure:
            path.addRoundedRect(in: CGRect(x: 5, y: 2, width: 14, height: 18), cornerSize: CGSize(width: 1.2, height: 1.2))
            path.move(to: CGPoint(x: 8, y: 6))
            path.addLine(to: CGPoint(x: 12, y: 9))
            path.addLine(to: CGPoint(x: 10, y: 13))
            path.addLine(to: CGPoint(x: 15, y: 16))
            path.addLine(to: CGPoint(x: 15, y: 16.8))
            path.addLine(to: CGPoint(x: 9, y: 13.4))
            path.addLine(to: CGPoint(x: 11.2, y: 9.2))
            path.addLine(to: CGPoint(x: 7.2, y: 6.6))
            path.closeSubpath()
        case .animation, .gameShow, .miniSeries, .soap, .generic:
            path.addEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
            path.addEllipse(in: CGRect(x: 7.2, y: 7.2, width: 9.6, height: 9.6))
            path.addEllipse(in: CGRect(x: 10.2, y: 10.2, width: 3.6, height: 3.6))
        case .anime:
            path.move(to: CGPoint(x: 12, y: 2))
            path.addLine(to: CGPoint(x: 14.2, y: 9))
            path.addLine(to: CGPoint(x: 22, y: 12))
            path.addLine(to: CGPoint(x: 14.2, y: 15))
            path.addLine(to: CGPoint(x: 12, y: 22))
            path.addLine(to: CGPoint(x: 9.8, y: 15))
            path.addLine(to: CGPoint(x: 2, y: 12))
            path.addLine(to: CGPoint(x: 9.8, y: 9))
            path.closeSubpath()
        case .comedy:
            mask(&path, smile: true)
        case .drama:
            mask(&path, smile: false)
        case .crime:
            path.addEllipse(in: CGRect(x: 1.5, y: 7.5, width: 8, height: 8))
            path.addEllipse(in: CGRect(x: 3.7, y: 9.7, width: 3.6, height: 3.6))
            path.addEllipse(in: CGRect(x: 14.5, y: 7.5, width: 8, height: 8))
            path.addEllipse(in: CGRect(x: 16.7, y: 9.7, width: 3.6, height: 3.6))
            path.addRoundedRect(in: CGRect(x: 9.2, y: 10.2, width: 5.6, height: 2.6), cornerSize: CGSize(width: 0.6, height: 0.6))
        case .documentary:
            path.addRoundedRect(in: CGRect(x: 4, y: 3, width: 16, height: 18), cornerSize: CGSize(width: 1.4, height: 1.4))
            path.addRect(CGRect(x: 4, y: 7.2, width: 16, height: 2.2))
            path.addRect(CGRect(x: 7, y: 12, width: 10, height: 1.6))
            path.addRect(CGRect(x: 7, y: 15.4, width: 7, height: 1.6))
        case .family, .children:
            path.addEllipse(in: CGRect(x: 2, y: 4, width: 6, height: 6))
            path.addEllipse(in: CGRect(x: 9, y: 3, width: 6, height: 6))
            path.addEllipse(in: CGRect(x: 16, y: 4.4, width: 5.2, height: 5.2))
            path.addRoundedRect(in: CGRect(x: 1, y: 12, width: 8, height: 9), cornerSize: CGSize(width: 3, height: 3))
            path.addRoundedRect(in: CGRect(x: 8, y: 11, width: 8, height: 10), cornerSize: CGSize(width: 3, height: 3))
            path.addRoundedRect(in: CGRect(x: 15.2, y: 12.2, width: 7, height: 8.6), cornerSize: CGSize(width: 3, height: 3))
        case .fantasy, .historical:
            path.addRect(CGRect(x: 3, y: 12, width: 18, height: 9))
            path.addRect(CGRect(x: 2, y: 8, width: 4, height: 13))
            path.addRect(CGRect(x: 10, y: 6, width: 4, height: 15))
            path.addRect(CGRect(x: 18, y: 8, width: 4, height: 13))
            path.move(to: CGPoint(x: 2, y: 8))
            path.addLine(to: CGPoint(x: 4, y: 3))
            path.addLine(to: CGPoint(x: 6, y: 8))
            path.closeSubpath()
            path.move(to: CGPoint(x: 10, y: 6))
            path.addLine(to: CGPoint(x: 12, y: 1.5))
            path.addLine(to: CGPoint(x: 14, y: 6))
            path.closeSubpath()
            path.move(to: CGPoint(x: 18, y: 8))
            path.addLine(to: CGPoint(x: 20, y: 3))
            path.addLine(to: CGPoint(x: 22, y: 8))
            path.closeSubpath()
        case .food:
            path.addRoundedRect(in: CGRect(x: 4, y: 4.2, width: 2.2, height: 17.5), cornerSize: CGSize(width: 1, height: 1))
            path.addRoundedRect(in: CGRect(x: 8.2, y: 4.2, width: 2.2, height: 17.5), cornerSize: CGSize(width: 1, height: 1))
            path.addRoundedRect(in: CGRect(x: 12.4, y: 4.2, width: 2.2, height: 17.5), cornerSize: CGSize(width: 1, height: 1))
            path.addRoundedRect(in: CGRect(x: 3.2, y: 2, width: 12.2, height: 2.2), cornerSize: CGSize(width: 1, height: 1))
        case .holiday:
            path.addRoundedRect(in: CGRect(x: 3, y: 8, width: 18, height: 13), cornerSize: CGSize(width: 1.5, height: 1.5))
            path.addRect(CGRect(x: 10.6, y: 8, width: 2.8, height: 13))
            path.addRect(CGRect(x: 3, y: 12.4, width: 18, height: 2.8))
            path.addEllipse(in: CGRect(x: 8, y: 3, width: 4, height: 4))
            path.addEllipse(in: CGRect(x: 12, y: 3, width: 4, height: 4))
        case .horror, .supernatural:
            path.move(to: CGPoint(x: 4, y: 12))
            path.addQuadCurve(to: CGPoint(x: 12, y: 3), control: CGPoint(x: 4, y: 3))
            path.addQuadCurve(to: CGPoint(x: 20, y: 12), control: CGPoint(x: 20, y: 3))
            path.addLine(to: CGPoint(x: 20, y: 20))
            path.addLine(to: CGPoint(x: 16.5, y: 16.5))
            path.addLine(to: CGPoint(x: 13.5, y: 21))
            path.addLine(to: CGPoint(x: 10.5, y: 16.5))
            path.addLine(to: CGPoint(x: 7.5, y: 21))
            path.addLine(to: CGPoint(x: 4, y: 16.5))
            path.closeSubpath()
        case .music:
            path.addEllipse(in: CGRect(x: 3, y: 14, width: 6, height: 5))
            path.addEllipse(in: CGRect(x: 13, y: 12, width: 6, height: 5))
            path.addRect(CGRect(x: 8, y: 4, width: 1.8, height: 12))
            path.addRect(CGRect(x: 18, y: 3, width: 1.8, height: 11))
            path.addRoundedRect(in: CGRect(x: 8, y: 3, width: 12, height: 2.4), cornerSize: CGSize(width: 0.6, height: 0.6))
        case .mystery:
            path.addEllipse(in: CGRect(x: 2, y: 10, width: 14, height: 8))
            path.addRoundedRect(in: CGRect(x: 4, y: 3, width: 12, height: 4), cornerSize: CGSize(width: 1, height: 1))
            path.addRect(CGRect(x: 15, y: 6, width: 7, height: 1.6))
            path.addEllipse(in: CGRect(x: 15, y: 15, width: 6.5, height: 6.5))
            path.addEllipse(in: CGRect(x: 16.6, y: 16.6, width: 3.3, height: 3.3))
        case .nature:
            path.addEllipse(in: CGRect(x: 8, y: 2, width: 8, height: 8))
            path.addEllipse(in: CGRect(x: 2, y: 12, width: 9, height: 7))
            path.addEllipse(in: CGRect(x: 8, y: 10, width: 10, height: 9))
            path.addEllipse(in: CGRect(x: 14, y: 13, width: 8, height: 6))
        case .news:
            path.addRoundedRect(in: CGRect(x: 3, y: 4, width: 18, height: 16), cornerSize: CGSize(width: 1.2, height: 1.2))
            path.addRect(CGRect(x: 6, y: 7, width: 12, height: 2))
            path.addRect(CGRect(x: 6, y: 11, width: 12, height: 1.6))
            path.addRect(CGRect(x: 6, y: 14.4, width: 8, height: 1.6))
        case .reality:
            path.addRoundedRect(in: CGRect(x: 2, y: 7, width: 13, height: 10), cornerSize: CGSize(width: 1.5, height: 1.5))
            path.move(to: CGPoint(x: 15, y: 9))
            path.addLine(to: CGPoint(x: 22, y: 6))
            path.addLine(to: CGPoint(x: 22, y: 18))
            path.addLine(to: CGPoint(x: 15, y: 15))
            path.closeSubpath()
        case .romance:
            path.move(to: CGPoint(x: 12, y: 20.5))
            path.addQuadCurve(to: CGPoint(x: 2, y: 9), control: CGPoint(x: 2, y: 16))
            path.addQuadCurve(to: CGPoint(x: 7.5, y: 4), control: CGPoint(x: 2, y: 4))
            path.addQuadCurve(to: CGPoint(x: 12, y: 8), control: CGPoint(x: 10, y: 4))
            path.addQuadCurve(to: CGPoint(x: 16.5, y: 4), control: CGPoint(x: 14, y: 4))
            path.addQuadCurve(to: CGPoint(x: 22, y: 9), control: CGPoint(x: 22, y: 4))
            path.addQuadCurve(to: CGPoint(x: 12, y: 20.5), control: CGPoint(x: 22, y: 16))
            path.closeSubpath()
        case .scienceFiction, .sciFiFantasy:
            path.addEllipse(in: CGRect(x: 4, y: 9, width: 16, height: 6))
            path.addEllipse(in: CGRect(x: 9, y: 4, width: 6, height: 6))
            path.addRect(CGRect(x: 11.2, y: 15, width: 1.6, height: 4))
            path.addEllipse(in: CGRect(x: 6, y: 18, width: 3, height: 2))
            path.addEllipse(in: CGRect(x: 15, y: 18, width: 3, height: 2))
        case .sport:
            path.addEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
        case .superhero, .war:
            path.move(to: CGPoint(x: 12, y: 2))
            path.addLine(to: CGPoint(x: 21, y: 6))
            path.addLine(to: CGPoint(x: 21, y: 12))
            path.addQuadCurve(to: CGPoint(x: 12, y: 22), control: CGPoint(x: 21, y: 18))
            path.addQuadCurve(to: CGPoint(x: 3, y: 12), control: CGPoint(x: 3, y: 18))
            path.addLine(to: CGPoint(x: 3, y: 6))
            path.closeSubpath()
        case .suspense, .biography:
            path.addEllipse(in: CGRect(x: 6, y: 2, width: 12, height: 12))
            path.addRoundedRect(in: CGRect(x: 3, y: 15, width: 18, height: 7), cornerSize: CGSize(width: 3, height: 3))
            path.addEllipse(in: CGRect(x: 9.5, y: 6, width: 5, height: 5))
        case .thriller:
            path.move(to: CGPoint(x: 14, y: 2))
            path.addLine(to: CGPoint(x: 18, y: 2))
            path.addLine(to: CGPoint(x: 11, y: 16))
            path.addLine(to: CGPoint(x: 7, y: 16))
            path.closeSubpath()
            path.addRoundedRect(in: CGRect(x: 6, y: 16, width: 6, height: 5), cornerSize: CGSize(width: 1, height: 1))
        case .western:
            path.move(to: CGPoint(x: 7, y: 2))
            path.addLine(to: CGPoint(x: 16, y: 2))
            path.addLine(to: CGPoint(x: 16, y: 8))
            path.addLine(to: CGPoint(x: 20, y: 12))
            path.addLine(to: CGPoint(x: 16, y: 16))
            path.addLine(to: CGPoint(x: 14, y: 22))
            path.addLine(to: CGPoint(x: 8, y: 22))
            path.addLine(to: CGPoint(x: 7, y: 14))
            path.addLine(to: CGPoint(x: 4, y: 12))
            path.addLine(to: CGPoint(x: 7, y: 8))
            path.closeSubpath()
        }
        return path
    }

    private func mask(_ path: inout Path, smile: Bool) {
        path.addEllipse(in: CGRect(x: 3, y: 2, width: 18, height: 20))
        path.addEllipse(in: CGRect(x: 7.2, y: 8, width: 2.4, height: 3))
        path.addEllipse(in: CGRect(x: 14.4, y: 8, width: 2.4, height: 3))
        if smile {
            path.move(to: CGPoint(x: 8, y: 14))
            path.addQuadCurve(to: CGPoint(x: 16, y: 14), control: CGPoint(x: 12, y: 18))
            path.addQuadCurve(to: CGPoint(x: 8, y: 14), control: CGPoint(x: 12, y: 15))
        } else {
            path.move(to: CGPoint(x: 8, y: 16))
            path.addQuadCurve(to: CGPoint(x: 16, y: 16), control: CGPoint(x: 12, y: 12))
            path.addQuadCurve(to: CGPoint(x: 8, y: 16), control: CGPoint(x: 12, y: 15))
        }
    }
}
