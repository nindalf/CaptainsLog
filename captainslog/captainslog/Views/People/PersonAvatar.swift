import SwiftUI

/// A circle with the person's initials, tinted by a hash of their name so the same person
/// keeps the same colour across launches and stores.
struct PersonAvatar: View {
    let name: String
    var size: CGFloat = 32

    private static let palette: [Color] = [
        .blue, .green, .orange, .pink, .purple, .teal, .indigo, .brown, .mint, .cyan,
    ]

    var body: some View {
        ZStack {
            Circle().fill(color.gradient)
            if let initials {
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// First letters of the first and last words that start with a letter.
    private var initials: String? {
        let words = name.split(whereSeparator: \.isWhitespace).filter { $0.first?.isLetter == true }
        guard let first = words.first?.first else { return nil }
        guard words.count > 1, let last = words.last?.first else { return String(first).uppercased() }
        return (String(first) + String(last)).uppercased()
    }

    /// FNV-1a over the name: `hashValue` is seeded per process, so it would reshuffle colours.
    private var color: Color {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in name.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return Self.palette[Int(hash % UInt64(Self.palette.count))]
    }
}

#Preview {
    HStack {
        PersonAvatar(name: "Ada Lovelace")
        PersonAvatar(name: "Grace Brewster Murray Hopper")
        PersonAvatar(name: "linus")
        PersonAvatar(name: "")
    }
    .padding()
}
