import XCTest
@testable import Pleats

/// Each song is compared with an independent public-domain transcription (abcnotation.com, see
/// scripts/verify-melodies.py and scripts/melody-reference.json): the opening intervals, which do not depend on the
/// key, must appear in the song. Songs checked by hand (no reliable transcription found) are listed in the
/// melody script output; originals written for Pleats have no reference.
final class MelodyReferenceTests: XCTestCase {
    /// song id → (minimum share of matching intervals, reference intervals)
    static let references: [String: (Double, [Int])] = [
        "auldlang": (0.9, [5, 0, 0, 4, -2, -2, 2, 2, -4, 0, 4, 3, 2, 3, -5, -3, 0, -4, 2, -2]),  // colinhume.com/ABC.txt/0061
        "cucaracha": (1.0, [0, 0, 5, 4, -9, 0, 0, 5, 4, -4, 0, -1, 0, -2, 0, -2, 0, 0, 0, 4]),  // trillian.mit.edu/~jc/music/abc/mirror/musicaviva.com/anon/la-cucaracha/la-cucaracha-1/0000
        "elise": (1.0, [-1, 1, -1, 1, -5, 3, -2, -3, -9, 4, 5, 2, -7, 4, 3, 1, -8, 12, -1, 1]),  // trillian.mit.edu/~jc/music/abc/mirror/LesterBailey/melnets_big_abc_file/04347
        "entertainer": (1.0, [1, 1, 8, -8, 8, -8, 8, 0, 2, 1, 1, -4, 2, 2, -5, 3, -2, -10, 1, 1]),  // colinhume.com/ABC.txt/0435
        "grace": (1.0, [5, 4, -4, 4, -2, -2, -3, -2, 0, 5, 4, -4, 4, -2, 5, -3, 3, -3, -4, 4]),  // colinhume.com/ABC.txt/0030
        "jingle": (1.0, [0, 0, 0, 0, 0, 0, 3, -7, 2, 2, 1, 0, 0, 0, 0, -1, 0, 0, 0, 0]),  // colinhume.com/ABC.txt/0692
        "ode": (1.0, [0, 1, 2, 0, -2, -1, -2, -2, 0, 2, 2, 0, -2, 0, 2, 0, 1, 2, 0, -2]),  // gitlab.com/chrisspen/abc-music/abc-music-master.zip/abc-music-master/12-string-baroque-lut
        "sailor": (1.0, [0, 0, 0, 0, 0, 0, -7, 3, 4, -2, 0, 0, 0, 0, 0, 0, -7, 4, 3, 2]),  // pghardy.net/tunebooks/pgh_session_tunebook/0168
        "saints": (0.95, [4, 1, 2, -7, 4, 1, 2, -7, 4, 1, 2, -3, -4, 4, -2, 2, 0, -2, -2, 4]),  // trillian.mit.edu/~jc/music/abc/demo/Tunes/WhenTheSaintsGoMarchingIn/0000
        "sarigelin": (1.0, [0, 7, 0, -2, 2, -2, 2, 0, 0, 1, -1, -2, 0, -2, 2, 2, 0, 2, -4, -2]),  // www.campin.me.uk/Music/Chalumeau/0360
        "susanna": (1.0, [2, 2, 3, 0, 2, -2, -3, -4, 2, 2, 0, -2, -2, 2, -2, 2, 2, 3, 0, 2]),  // abc.sourceforge.net/NMD/nmd/reelsr-t.txt/0062
        "uskudar": (1.0, [7, 0, 0, 1, -1, 1, 2, -3, 0, -2, 0, 0, -2, 2, 2, 1, -1, -2, -2, -1]),  // trillian.mit.edu/~jc/music/abc/mirror/SeymourShlien/makams/makamu21/0033
        "yemen": (1.0, [2, 2, 0, 0, 0, 1, -3, 2, -2, 2, -2, 2, -2, 0, 5, 0, -5, 0, 2, -4]),  // trillian.mit.edu/~jc/music/abc/mirror/SeymourShlien/makams/makamu9/0081
    ]

    func testSongsMatchReferenceTranscriptions() {
        for (id, ref) in Self.references {
            guard let song = SongBook.song(id) else { XCTFail("missing song \(id)"); continue }
            let ps = song.playable.map { $0.pitch! }
            let mine = zip(ps.dropFirst(), ps).map { $0 - $1 }
            var best = 0
            for off in 0..<max(1, mine.count - 4) {
                let hits = zip(mine.dropFirst(off), ref.1).filter { $0 == $1 }.count
                best = max(best, hits)
            }
            let need = Int((ref.0 * Double(ref.1.count)).rounded(.down))
            XCTAssertGreaterThanOrEqual(best, need, "\(id): \(best)/\(ref.1.count) opening intervals match the reference")
        }
        XCTAssertGreaterThanOrEqual(Self.references.count, 12)
    }
}
