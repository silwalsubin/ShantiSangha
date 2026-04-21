import Foundation

/// Plain-language explanations of the core Jyotish concepts shown on the
/// Birth Chart page. Each "What this means" disclosure pairs one of these
/// concept paragraphs with the classical corpus passage for the user's
/// specific placement — so the user learns BOTH what the concept is in
/// Jyotish AND what the tradition says about their own chart.
///
/// Content is intentionally casual, second-person, no Sanskrit-glossing,
/// no mystification. It reads the way a thoughtful teacher explains things.
/// Not translated, not quoted — written for this app's voice.
enum JyotishMeanings {

    // MARK: - Concepts (one per chart element)

    static let nakshatra = """
        A nakshatra is the lunar mansion — the star group the Moon was passing \
        through when you were born. Classical Jyotish reads it as the inner \
        weather of your life: how you feel things, what settles you, what \
        stirs you up. Every 27 days the Moon returns to yours, and its quality \
        quietly touches the day.
        """

    static let lagna = """
        Your lagna (ascendant) is the zodiac sign that was rising on the \
        eastern horizon at the exact minute you were born. It's read as the \
        shape of your personality — how people meet you before they know you, \
        the body you live in, the way you walk into a room. If the rashi is \
        the inner weather, the lagna is the weather report people see.
        """

    static let dasha = """
        A dasha is the planetary season currently running through your life. \
        Jyotish divides each lifetime into nested periods ruled by different \
        planets — the Mahadasha is the chapter you're in, the Antardasha is \
        the current page. When the season changes, the texture of the years \
        changes with it.
        """

    // MARK: - Planets

    /// Returns the plain-English description of what this planet signifies
    /// in Jyotish. Used on PlanetDetailView above the classical passage.
    static func planet(_ name: String) -> String {
        switch name {
        case "Sun":
            return """
                The Sun is the self — who you show up as in the world, where \
                you want to shine, what you take pride in. Where it sits in \
                your chart tells you where your identity most wants to be seen.
                """
        case "Moon":
            return """
                The Moon is your mind and emotional life — what you feel, how \
                you rest, what comforts you. Jyotish treats the Moon as the \
                primary signifier of who you are inwardly, more than the Sun.
                """
        case "Mars":
            return """
                Mars is your fight — your energy, your courage, how you push \
                when something needs pushing. Where it sits shows where you \
                apply heat in your life, and where impatience tends to surface.
                """
        case "Mercury":
            return """
                Mercury is your voice and your thinking — how you speak, how \
                you analyse, how you learn. Its placement points to where your \
                curiosity lives and how you make sense of what's in front of you.
                """
        case "Jupiter":
            return """
                Jupiter is your wisdom and your faith — what you believe, how \
                you grow, where you find meaning. Jyotish treats Jupiter as \
                the great protector; where it sits tends to soften and expand.
                """
        case "Venus":
            return """
                Venus is your love and your beauty — what you're drawn to, how \
                you relate, what you create. Its placement shows where pleasure, \
                partnership, and aesthetic sense most easily flow for you.
                """
        case "Saturn":
            return """
                Saturn is your discipline and your limits — what you're building, \
                what you're carrying, what shapes you through time. Saturn's \
                house is where life asks you to grow up slowly, and where the \
                deepest mastery eventually comes.
                """
        case "Rahu":
            return """
                Rahu is the shadow that pulls you forward — the hunger that \
                won't let you settle, the new thing you're reaching for this \
                lifetime. Where it sits often feels unfamiliar, restless, and \
                magnetically important.
                """
        case "Ketu":
            return """
                Ketu is the shadow that pulls you inward — what you're \
                releasing, what you've already mastered, where you're meant to \
                let go. Ketu's house is often where you feel competent but \
                strangely uninterested, already done with the lesson.
                """
        default:
            return """
                In Jyotish each planet carries a character, and the house it \
                sits in tells you where that character gets lived out in your life.
                """
        }
    }
}
