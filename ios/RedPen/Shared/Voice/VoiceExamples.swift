import Foundation

/// Finished examples of the spoken modes, for a personal build.
///
/// A marked explanation or a marked station is the whole point of those
/// screens, and without an example the only way to see one is to talk for
/// five minutes first. These show up in each screen's past attempts, labelled
/// "Example", and are never saved or synced.
enum VoiceExamples {

    // MARK: explain it back

    static let explainAttempts: [ExplainAttempt] = [inguinalCanal]

    static let inguinalCanal = ExplainAttempt(
        date: Date(timeIntervalSince1970: 1_790_000_000),
        topic: "The inguinal canal",
        setName: "Example",
        transcript: """
        OK so the inguinal canal is a passage through the lower anterior abdominal wall, it's about four centimetres long and it runs from the deep ring to the superficial ring. The deep ring is a hole in the transversalis fascia, and it sits at the midpoint of the inguinal ligament, just lateral to the inferior epigastric vessels. The superficial ring is a defect in the external oblique aponeurosis, above and medial to the pubic tubercle. In men it carries the spermatic cord and in women the round ligament, and in both it carries the ilioinguinal nerve. For the walls, the anterior wall is external oblique aponeurosis, the floor is the inguinal ligament, and the roof is internal oblique and transversus abdominis. The posterior wall is the conjoint tendon. An indirect hernia goes through the deep ring, lateral to the inferior epigastrics, and a direct hernia comes through Hesselbach's triangle, which is medial to them.
        """,
        result: ExplainResult(
            covered: [
                "About 4 cm long, running from the deep to the superficial ring",
                "Deep ring: an opening in the transversalis fascia, lateral to the inferior epigastric vessels",
                "Superficial ring: a defect in the external oblique aponeurosis, above and medial to the pubic tubercle",
                "Contents: spermatic cord (male), round ligament (female), ilioinguinal nerve",
                "Anterior wall external oblique aponeurosis; floor the inguinal ligament; roof internal oblique and transversus abdominis",
                "Indirect hernias pass through the deep ring, lateral to the inferior epigastric vessels; direct hernias through Hesselbach's triangle, medial to them",
            ],
            missed: [
                "The anterior wall is reinforced laterally by internal oblique",
                "The posterior wall is transversalis fascia throughout, reinforced medially by the conjoint tendon",
                "Why the canal is oblique: raised abdominal pressure presses the posterior wall against the anterior, closing it like a shutter",
                "The boundaries of Hesselbach's triangle: inferior epigastric vessels, lateral border of rectus abdominis, inguinal ligament",
                "The contents of the spermatic cord (three arteries, three nerves, three other structures)",
            ],
            wrong: [
                "You said the posterior wall IS the conjoint tendon. It is transversalis fascia, with the conjoint tendon reinforcing only its medial part.",
            ],
            score: 71,
            oneTip: "Describe each wall with its reinforcement - 'anterior: external oblique, plus internal oblique laterally; posterior: transversalis fascia, plus conjoint tendon medially' - because the reinforcements are what explain where hernias come through."
        ),
        isExample: true
    )

    // MARK: spoken stations

    static let stationAttempts: [StationAttempt] = [chestPainHistory, breakingBadNews]

    static let chestPainHistory = StationAttempt(
        date: Date(timeIntervalSince1970: 1_790_100_000),
        title: "History: chest pain in a 58-year-old man",
        steps: [
            "Introduces self, confirms patient identity, gains consent",
            "Asks about onset, character and site of the pain",
            "Asks about radiation, associated symptoms (breathlessness, sweating, nausea)",
            "Asks about exacerbating and relieving factors, including exertion and rest",
            "Asks about cardiovascular risk factors (smoking, diabetes, hypertension, cholesterol, family history)",
            "Takes a drug history and allergies",
            "Explores ideas, concerns and expectations",
            "Summarises and gives a sensible differential (acute coronary syndrome first)",
        ],
        lines: [
            SpokenLine(speaker: .examiner, text: "This is Mr Harris, 58, who has come to the emergency department with chest pain. Take a focused history. You have eight minutes."),
            SpokenLine(speaker: .student, text: "Hello, I'm one of the medical students. Could you tell me your full name and date of birth? Is it OK if I ask you some questions about what's brought you in?"),
            SpokenLine(speaker: .patient, text: "Yes, of course. Peter Harris, twelfth of March. It's this pain in my chest, doctor."),
            SpokenLine(speaker: .student, text: "When did it start and what does it feel like?"),
            SpokenLine(speaker: .patient, text: "About an hour ago, while I was carrying the shopping in. It's like a heavy weight, right in the middle."),
            SpokenLine(speaker: .student, text: "Does it go anywhere else? Anything else with it, like feeling sick or sweaty or short of breath?"),
            SpokenLine(speaker: .patient, text: "It goes into my left arm and my jaw. I was sweating a lot, and I felt a bit sick."),
            SpokenLine(speaker: .student, text: "Do you smoke, and do you have diabetes, high blood pressure or high cholesterol?"),
            SpokenLine(speaker: .patient, text: "Twenty a day for thirty years. I'm on a tablet for blood pressure, amlodipine I think."),
            SpokenLine(speaker: .student, text: "Thank you. So you've had an hour of heavy central chest pain going to your arm and jaw, with sweating, and you smoke and have high blood pressure. I'm worried this could be your heart, a heart attack, and I'd like to do an ECG and some blood tests straight away."),
        ],
        mark: StationMark(
            done: [0, 1, 2, 4, 7],
            missedNotes: ["Never asked what makes the pain better or worse", "No drug history beyond one drug, and no allergies", "Did not ask what Mr Harris was worried about"],
            communication: 4,
            feedback: "A clear, well-ordered history of the pain with a safe summary and the right first diagnosis. You missed exacerbating and relieving factors, a full drug history with allergies, and his ideas, concerns and expectations - ask 'Is there anything you've been worrying it might be?' before summarising."
        ),
        isCommunication: false,
        isExample: true
    )

    static let breakingBadNews = StationAttempt(
        date: Date(timeIntervalSince1970: 1_790_200_000),
        title: "Breaking bad news: CT shows likely lung cancer",
        steps: [
            "Prepares the setting: private room, introduces self, checks who the patient would like present",
            "Establishes what the patient knows about why the scan was done",
            "Asks how much the patient would like to know",
            "Gives a warning shot, then the news in plain language without jargon",
            "Pauses, acknowledges emotion and responds with empathy",
            "Explains the next steps (biopsy, specialist team) and gives a plan",
            "Checks understanding and invites questions",
            "Offers support (specialist nurse, written information) and arranges follow-up",
        ],
        lines: [
            SpokenLine(speaker: .examiner, text: "Mrs Okafor, 64, had a CT chest last week for a persistent cough. It shows a 3 cm mass in the right upper lobe, likely to be lung cancer. Explain the result to her. You have eight minutes."),
            SpokenLine(speaker: .student, text: "Hello Mrs Okafor, I'm one of the doctors. Thank you for coming in. Is it all right to talk here, and would you like anyone with you?"),
            SpokenLine(speaker: .patient, text: "No, it's fine, my daughter's parking the car. Is it the scan results?"),
            SpokenLine(speaker: .student, text: "It is. Before I go through it, can you tell me what you understood about why we did the scan?"),
            SpokenLine(speaker: .patient, text: "The cough hasn't gone for two months. The GP said they wanted to rule things out."),
            SpokenLine(speaker: .student, text: "I'm afraid the scan has shown something worrying. There's a shadow, a lump, in the top of your right lung, and it looks like it could be a cancer."),
            SpokenLine(speaker: .patient, text: "Cancer? Oh my God. I knew it. I knew something was wrong."),
            SpokenLine(speaker: .student, text: "The next step is a biopsy to confirm it, and then a CT PET to stage it, and the MDT will discuss treatment options, which might be surgery or SABR or chemo."),
            SpokenLine(speaker: .patient, text: "I don't understand what any of that means. Am I going to die?"),
            SpokenLine(speaker: .student, text: "I'm sorry, this is a lot to take in. We don't know yet how far it has spread, and there are treatments. I'll get you a leaflet and the lung cancer nurse's number."),
        ],
        mark: StationMark(
            done: [0, 1, 3, 7],
            missedNotes: ["Did not ask how much she wanted to know", "Jumped to biopsy, PET and MDT jargon straight after the news, before responding to her shock", "Never checked her understanding or invited questions"],
            communication: 3,
            feedback: "A good start: you checked the setting, found out what she knew and gave a warning shot before the news. After the news, you went straight into 'CT PET', 'MDT' and 'SABR' while she was still in shock. Stop, stay silent, name the emotion ('This is a real shock') and only give the plan in plain words once she is ready. Then check what she has understood.",
            spikes: ["S": true, "P": true, "I": false, "K": true, "E": false, "S2": false]
        ),
        isCommunication: true,
        isExample: true
    )
}
